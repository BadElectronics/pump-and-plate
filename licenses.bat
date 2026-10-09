@echo off
setlocal EnableExtensions
title FitApp: accept Android licenses
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

echo.
echo  Android asks you to accept its licenses once.
echo  For each question, type y and press Enter.
echo.
call flutter doctor --android-licenses
echo.
echo  Done. Next step: double-click build.bat
echo.
pause
exit /b 0
