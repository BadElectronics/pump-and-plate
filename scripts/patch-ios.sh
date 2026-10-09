#!/usr/bin/env bash
# Adds Pump and Plate's iPhone settings to the iOS project that
# "flutter create . --platforms=ios" makes. Run from the app folder on a Mac
# (the cloud build does this). Safe to run more than once.
#
#   bash ../scripts/patch-ios.sh
set -euo pipefail

APP_DIR="${1:-.}"
SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
cd "$APP_DIR"

PLIST=ios/Runner/Info.plist
PBX=ios/Runner.xcodeproj/project.pbxproj
PODFILE=ios/Podfile
BUNDLE_ID=com.pumpandplate.app
MIN_IOS=16.0

if [ ! -f "$PLIST" ] || [ ! -f "$PBX" ]; then
  echo "No iOS project here. Run: flutter create . --platforms=ios --org com.fitapp --project-name fitapp" >&2
  exit 1
fi

str() { plutil -replace "$1" -string "$2" "$PLIST"; }

# ---------------------------------------------------------------- Info.plist
str CFBundleDisplayName "Pump and Plate"
str NSCameraUsageDescription "Pump and Plate uses the camera to scan food barcodes and take progress photos. Photos stay on your iPhone."
str NSPhotoLibraryUsageDescription "Pick a photo to add to Pump and Plate. It stays on your iPhone."
str NSFaceIDUsageDescription "Unlock Pump and Plate with Face ID."
# The camera package can record sound; Pump and Plate never does, but iOS
# needs the reason written down anyway.
str NSMicrophoneUsageDescription "Pump and Plate doesn't record sound. iOS asks every app that uses the camera to explain this."
# Only standard HTTPS: no export paperwork needed.
plutil -replace ITSAppUsesNonExemptEncryption -bool NO "$PLIST"
# Portrait only, like the Android app.
plutil -replace UISupportedInterfaceOrientations -json '["UIInterfaceOrientationPortrait"]' "$PLIST"
plutil -remove 'UISupportedInterfaceOrientations~ipad' "$PLIST" >/dev/null 2>&1 || true

# ------------------------------------------------------------ project.pbxproj
# The app's ID, the oldest iOS it runs on, and iPhone only for now (iPad and
# iPhone Duo layouts come in the big-screens phase).
sed -i '' -E "s/PRODUCT_BUNDLE_IDENTIFIER = com\.fitapp\.fitapp/PRODUCT_BUNDLE_IDENTIFIER = ${BUNDLE_ID}/g" "$PBX"
sed -i '' -E "s/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;/IPHONEOS_DEPLOYMENT_TARGET = ${MIN_IOS};/g" "$PBX"
sed -i '' -E 's/TARGETED_DEVICE_FAMILY = "1,2";/TARGETED_DEVICE_FAMILY = 1;/g' "$PBX"

# More memory for the downloadable AI models.
cat > ios/Runner/Runner.entitlements <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.kernel.increased-memory-limit</key>
	<true/>
	<key>com.apple.developer.kernel.extended-virtual-addressing</key>
	<true/>
</dict>
</plist>
XML
if ! grep -q "CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements" "$PBX"; then
  sed -i '' -E 's#(INFOPLIST_FILE = Runner/Info.plist;)#\1\
				CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;#g' "$PBX"
fi

# -------------------------------------------------------------- AppDelegate
# Notifications: let the app show its own reminders while open and know which
# one was tapped (needed by flutter_local_notifications).
APPDELEGATE=ios/Runner/AppDelegate.swift
if [ -f "$APPDELEGATE" ] && ! grep -q "UNUserNotificationCenter" "$APPDELEGATE"; then
  sed -i '' -E 's/^( *)return super\.application\(application, didFinishLaunchingWithOptions: launchOptions\)$/\1UNUserNotificationCenter.current().delegate = self\
\1return super.application(application, didFinishLaunchingWithOptions: launchOptions)/' "$APPDELEGATE"
  sed -i '' -E 's/^import UIKit$/import UIKit\
import UserNotifications/' "$APPDELEGATE"
  grep -q "UNUserNotificationCenter" "$APPDELEGATE" \
    || echo "Note: AppDelegate.swift looks different than expected; the app sets the notification delegate itself."
fi

# ------------------------------------------------------------------ Podfile
if [ ! -f "$PODFILE" ]; then
  # Flutter writes the Podfile the first time it gets packages.
  flutter pub get >/dev/null
fi
if [ -f "$PODFILE" ]; then
  sed -i '' -E "s/^#? *platform :ios, '[0-9.]+'/platform :ios, '${MIN_IOS}'/" "$PODFILE"
  # The AI engine's libraries must be linked statically.
  sed -i '' -E "s/^( *)use_frameworks!$/\1use_frameworks! :linkage => :static/" "$PODFILE"
  # Every package builds for the same oldest iOS.
  if ! grep -q "PUMP_MIN_IOS" "$PODFILE"; then
    sed -i '' -E "s/^( *)flutter_additional_ios_build_settings\(target\)$/\1flutter_additional_ios_build_settings(target)\\
\1target.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '${MIN_IOS}' } # PUMP_MIN_IOS/" "$PODFILE"
  fi
fi

# ----------------------------------------------------------------- App icon
ICONSET=ios/Runner/Assets.xcassets/AppIcon.appiconset
if [ -f "$SCRIPTS/icons/ios/AppIcon-1024.png" ]; then
  rm -f "$ICONSET"/*.png
  cp "$SCRIPTS/icons/ios/AppIcon-1024.png" "$ICONSET/AppIcon-1024.png"
  cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
fi

echo "iOS project ready: ${BUNDLE_ID}, iOS ${MIN_IOS}+, iPhone only."
