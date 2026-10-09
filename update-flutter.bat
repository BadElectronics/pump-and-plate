@echo off
setlocal
rem Updates the Flutter that lives in tools\flutter to the latest stable version.
rem Needed once if build.bat says a package needs a newer Flutter SDK.
call "%~dp0scripts\env.bat"

if not exist "%TOOLS%\flutter\bin\flutter.bat" (
  echo [!] Flutter isn't installed yet. Run setup.bat first.
  goto :fail
)

echo Flutter you have now:
call flutter --version
echo.
echo Updating to the latest stable Flutter. This downloads a few hundred MB
echo and can take 5 to 15 minutes. Leave this window open until it finishes.
echo.
call flutter channel stable
if errorlevel 1 goto :fail
call flutter upgrade
if errorlevel 1 goto :fail

echo.
echo Flutter you have now:
call flutter --version
echo.
echo Done. Now run build.bat.
pause
exit /b 0

:fail
echo.
echo [!] The update didn't finish. Scroll up to the first error, or send me a screenshot of it.
pause
exit /b 1
