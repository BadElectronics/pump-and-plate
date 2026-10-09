import Flutter
import UIKit
import UserNotifications

/// Registers Pump and Plate's iPhone channels. They use the same names and
/// arguments as the Android code in MainActivity, so the Dart side is shared.
public class PumpNativePlugin: NSObject, FlutterPlugin {
  private let device = DeviceChannel()
  private let backup = BackupChannel()
  private let appleAI = AppleAIChannel()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = PumpNativePlugin()
    let messenger = registrar.messenger()

    let device = FlutterMethodChannel(name: "fitapp/device", binaryMessenger: messenger)
    device.setMethodCallHandler { call, result in instance.device.handle(call, result) }

    let backup = FlutterMethodChannel(name: "fitapp/backup", binaryMessenger: messenger)
    backup.setMethodCallHandler { call, result in instance.backup.handle(call, result) }

    let ai = FlutterMethodChannel(name: "fitapp/appleai", binaryMessenger: messenger)
    ai.setMethodCallHandler { call, result in instance.appleAI.handle(call, result) }

    let events = FlutterEventChannel(name: "fitapp/appleai/events", binaryMessenger: messenger)
    events.setStreamHandler(instance.appleAI)

    // Reminders and rest alerts need the app to answer for its own
    // notifications (to show them while it's open, and to know which one was
    // tapped). The setup script does this in AppDelegate; this is the backup.
    if UNUserNotificationCenter.current().delegate == nil,
      let delegate = UIApplication.shared.delegate as? UNUserNotificationCenterDelegate
    {
      UNUserNotificationCenter.current().delegate = delegate
    }
  }
}

/// The screen currently on top, to show system pickers from.
func pumpTopViewController() -> UIViewController? {
  let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
  let windows = scenes.flatMap { $0.windows }
  let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first
  var top = window?.rootViewController
  while let presented = top?.presentedViewController {
    top = presented
  }
  return top
}

/// Calls a Flutter result on the main thread, which the engine requires.
func pumpReply(_ result: @escaping FlutterResult, _ value: Any?) {
  if Thread.isMainThread {
    result(value)
  } else {
    DispatchQueue.main.async { result(value) }
  }
}
