@echo off
setlocal EnableExtensions
title FitApp: install Android platform
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

echo.
echo  Installing the Android 16 platform and build tools into %ANDROID_HOME%
echo  This downloads about 150 MB.
echo.
(for /l %%i in (1,1,60) do @echo y) | "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" --licenses >nul
call "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" --install "platforms;android-36" "build-tools;36.0.0"
if errorlevel 1 goto :fail

echo.
echo  Checking again. The Android toolchain line should now show [√]:
call flutter doctor
echo.
echo  Next step: double-click build.bat
echo.
pause
exit /b 0

:fail
echo.
echo [!] The install failed. Send me a screenshot of the error above.
pause
exit /b 1
