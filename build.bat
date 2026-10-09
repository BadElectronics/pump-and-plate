@echo off
setlocal EnableExtensions
title FitApp build
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

if not exist "%TOOLS%\flutter\bin\flutter.bat" (
  echo [!] The build tools are not installed yet. Run setup.bat first.
  goto :fail
)

cd /d "%APP%"
if not exist "android\app" (
  echo Generating the Android project files...
  call flutter create . --platforms=android --org com.fitapp --project-name fitapp
  if errorlevel 1 goto :fail
)

rem Add the Android settings the app's packages need (only adds what's missing).
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\patch-android.ps1" -AppDir "%APP%"
if errorlevel 1 (
  echo [!] Could not update the Android project files. The message above says why.
  goto :fail
)

rem Put the saved signing key back if it is missing, so updates install over the old app.
if exist "%ROOT%\keys\debug.keystore" if not exist "%ANDROID_USER_HOME%\debug.keystore" (
  if not exist "%ANDROID_USER_HOME%" mkdir "%ANDROID_USER_HOME%"
  copy /y "%ROOT%\keys\debug.keystore" "%ANDROID_USER_HOME%\debug.keystore" >nul
  echo Restored the signing key from keys\debug.keystore
)

echo.
echo [1/3] Getting packages...
call flutter pub get
if errorlevel 1 (
  echo.
  echo [!] If the message above says a package needs a newer Flutter SDK,
  echo     run update-flutter.bat once, then run build.bat again.
  goto :fail
)

echo.
echo [2/3] Running tests...
call flutter test
if errorlevel 1 (
  echo [!] A test failed, so no APK was built. The failing test is listed above.
  goto :fail
)

set /p PHASE=<"%ROOT%\scripts\phase.txt"
set /p LAST=<"%ROOT%\scripts\build_number.txt"
set /a N=LAST+1
set "VERSION=1.%PHASE%.%N%"

echo.
echo [3/3] Building version %VERSION%. The first build takes several minutes...
call flutter build apk --release --target-platform android-arm64 --build-name %VERSION% --build-number %N%
if errorlevel 1 goto :fail

>"%ROOT%\scripts\build_number.txt" echo %N%
if not exist "%ROOT%\output" mkdir "%ROOT%\output"
copy /y "%APP%\build\app\outputs\flutter-apk\app-release.apk" "%ROOT%\output\fitapp-%VERSION%.apk" >nul
if errorlevel 1 goto :fail

rem Save the signing key the first time it exists.
if not exist "%ROOT%\keys" mkdir "%ROOT%\keys"
if not exist "%ROOT%\keys\debug.keystore" if exist "%ANDROID_USER_HOME%\debug.keystore" (
  copy /y "%ANDROID_USER_HOME%\debug.keystore" "%ROOT%\keys\debug.keystore" >nul
  echo Saved the signing key to keys\debug.keystore. Keep the keys folder safe.
)

echo.
echo  Done: %ROOT%\output\fitapp-%VERSION%.apk
echo  Install it with install.bat, or copy that file to your phone and tap it.
echo.
pause
exit /b 0

:fail
echo.
echo  Build stopped. Scroll up to the first error, or send me a screenshot of it.
echo.
pause
exit /b 1
