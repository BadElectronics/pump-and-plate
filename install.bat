@echo off
setlocal EnableExtensions
title FitApp install
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

set "APK="
for /f "delims=" %%F in ('dir /b /o-d "%ROOT%\output\*.apk" 2^>nul') do if not defined APK set "APK=%%F"
if not defined APK (
  echo [!] There is no APK in the output folder yet. Run build.bat first.
  goto :fail
)

adb start-server >nul 2>nul
set "DEVICE="
for /f "skip=1 tokens=1,2" %%A in ('adb devices') do if "%%B"=="device" set "DEVICE=%%A"
if not defined DEVICE (
  echo [!] No phone found. Check that:
  echo     1. The phone is plugged in with a USB cable that carries data.
  echo     2. USB debugging is on, in Settings, Developer options.
  echo     3. You tapped Allow on the phone's USB debugging prompt.
  goto :fail
)

echo Installing %APK%...
adb install -r "%ROOT%\output\%APK%"
if errorlevel 1 (
  echo [!] Install failed. If it mentions a signature or UPDATE_INCOMPATIBLE,
  echo     this APK was signed with a different key than the app on the phone.
  goto :fail
)
adb shell monkey -p com.fitapp.fitapp -c android.intent.category.LAUNCHER 1 >nul 2>nul
echo.
echo  Installed and opened on your phone.
echo.
pause
exit /b 0

:fail
echo.
pause
exit /b 1
