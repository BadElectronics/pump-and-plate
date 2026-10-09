@echo off
rem Everything lives inside this one project folder, on whatever drive it is on.
rem ROOT is the folder that contains setup.bat, build.bat and install.bat.
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "APP=%ROOT%\app"
set "TOOLS=%ROOT%\tools"

set "JAVA_HOME=%TOOLS%\jdk"
set "ANDROID_HOME=%TOOLS%\android-sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
rem Android settings and the signing key normally go to C:\Users\you\.android
set "ANDROID_USER_HOME=%TOOLS%\android-user"
rem Gradle's download cache normally goes to C:\Users\you\.gradle
set "GRADLE_USER_HOME=%TOOLS%\gradle"
rem Flutter's package cache normally goes to C:\Users\you\AppData
set "PUB_CACHE=%TOOLS%\pub-cache"
rem Temporary files from downloads and builds
set "TEMP=%TOOLS%\tmp"
set "TMP=%TOOLS%\tmp"
if not exist "%TOOLS%\tmp" mkdir "%TOOLS%\tmp" >nul 2>nul

set "PATH=%TOOLS%\flutter\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%TOOLS%\git\cmd;%PATH%"
set "FLUTTER_SUPPRESS_ANALYTICS=true"
