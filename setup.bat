@echo off
setlocal EnableExtensions
title FitApp setup
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

echo.
echo  FitApp one-time setup
echo  ---------------------
echo  Everything installs into %TOOLS%
echo  Nothing is installed on your C: drive.
echo  This downloads about 3-5 GB and takes roughly 20-40 minutes.
echo  You can close this window and run setup.bat again later; it skips finished steps.
echo.

set "HERE=%ROOT%"
set "NOSPACE=%HERE: =%"
if not "%NOSPACE%"=="%HERE%" goto :spaces

if not exist "%TOOLS%\_downloads" mkdir "%TOOLS%\_downloads"

call :ensure_git      || goto :fail
call :ensure_jdk      || goto :fail
call :ensure_flutter  || goto :fail
call :ensure_android  || goto :fail
call :prepare_flutter || goto :fail
call :create_project  || goto :fail

echo.
echo  Setup finished. Everything is in %ROOT%
echo  Next step: double-click build.bat
echo.
pause
exit /b 0


:ensure_git
if exist "%TOOLS%\git\cmd\git.exe" (echo [1/6] Git is already installed. & exit /b 0)
echo [1/6] Downloading a portable copy of Git, about 40 MB...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $r=Invoke-RestMethod -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{'User-Agent'='fitapp-setup'}; $a=$r.assets | Where-Object { $_.name -match '^MinGit-[0-9.]+-64-bit\.zip$' } | Select-Object -First 1; if (-not $a) { throw 'MinGit download not found' }; $z=Join-Path $env:TOOLS '_downloads\git.zip'; Invoke-WebRequest -Uri $a.browser_download_url -OutFile $z; Expand-Archive -Path $z -DestinationPath (Join-Path $env:TOOLS 'git') -Force; Remove-Item $z -Force"
if errorlevel 1 (
  echo [!] Git download failed. Check your internet connection and run setup.bat again.
  exit /b 1
)
if not exist "%TOOLS%\git\cmd\git.exe" (
  echo [!] Git did not end up in %TOOLS%\git. Delete that folder and run setup.bat again.
  exit /b 1
)
exit /b 0


:ensure_jdk
if exist "%JAVA_HOME%\bin\java.exe" (echo [2/6] Java is already installed. & exit /b 0)
echo [2/6] Downloading Java 17, about 190 MB...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $z=Join-Path $env:TOOLS '_downloads\jdk.zip'; Invoke-WebRequest -Uri 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse' -OutFile $z; $t=Join-Path $env:TOOLS 'jdk-tmp'; if (Test-Path $t) { Remove-Item $t -Recurse -Force }; Expand-Archive -Path $z -DestinationPath $t; $inner=Get-ChildItem $t -Directory | Select-Object -First 1; Move-Item $inner.FullName $env:JAVA_HOME; Remove-Item $t -Recurse -Force; Remove-Item $z -Force"
if errorlevel 1 (
  echo [!] Java download failed. Check your internet connection and run setup.bat again.
  exit /b 1
)
if not exist "%JAVA_HOME%\bin\java.exe" (
  echo [!] Java did not end up in %JAVA_HOME%. Delete that folder and run setup.bat again.
  exit /b 1
)
exit /b 0


:ensure_flutter
if exist "%TOOLS%\flutter\bin\flutter.bat" (echo [3/6] Flutter is already installed. & exit /b 0)
echo [3/6] Downloading Flutter, stable channel. This is the biggest step...
git clone https://github.com/flutter/flutter.git -b stable "%TOOLS%\flutter"
if errorlevel 1 (
  echo [!] Flutter download failed. Delete %TOOLS%\flutter and run setup.bat again.
  exit /b 1
)
exit /b 0


:ensure_android
if exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" goto :android_packages
echo [4/6] Downloading Android command-line tools...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $ProgressPreference='SilentlyContinue'; $z=Join-Path $env:TOOLS '_downloads\cmdline-tools.zip'; Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $z; $t=Join-Path $env:TOOLS 'cmdline-tmp'; if (Test-Path $t) { Remove-Item $t -Recurse -Force }; Expand-Archive -Path $z -DestinationPath $t; $dest=Join-Path $env:ANDROID_HOME 'cmdline-tools'; New-Item -ItemType Directory -Force -Path $dest | Out-Null; Move-Item (Join-Path $t 'cmdline-tools') (Join-Path $dest 'latest'); Remove-Item $t -Recurse -Force; Remove-Item $z -Force"
if errorlevel 1 (
  echo [!] Android tools download failed.
  echo     Manual fix: download "Command line tools only" for Windows from
  echo     https://developer.android.com/studio and unzip it so this file exists:
  echo     %ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat
  echo     Then run setup.bat again.
  exit /b 1
)

:android_packages
echo [4/6] Accepting Android licenses and installing the Android 16 platform...
(for /l %%i in (1,1,60) do @echo y) | "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" --licenses >nul
call "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
if errorlevel 1 (
  echo [!] Installing Android platform tools failed. Run setup.bat again.
  exit /b 1
)
exit /b 0


:prepare_flutter
echo [5/6] First Flutter run: downloading its Dart and Android pieces...
call flutter --version
if errorlevel 1 exit /b 1
call flutter precache --android
if errorlevel 1 exit /b 1
echo.
echo  Android asks you to accept its licenses. Type y and press Enter for each one.
call flutter doctor --android-licenses
exit /b 0


:create_project
cd /d "%APP%"
if exist "android\app" (echo [6/6] Android project files already exist. & goto :pub_get)
echo [6/6] Generating the Android project files...
call flutter create . --platforms=android --org com.fitapp --project-name fitapp
if errorlevel 1 exit /b 1
:pub_get
call flutter pub get
if errorlevel 1 exit /b 1
echo.
echo  Flutter health check. Ignore lines about Chrome, Visual Studio or Android Studio:
call flutter doctor
exit /b 0


:spaces
echo [!] This folder's path has spaces in it: %HERE%
echo     Move the project folder somewhere without spaces, for example Z:\fitapp
echo     Then run setup.bat again.
goto :fail


:fail
echo.
echo  Setup stopped before finishing. The message above says what went wrong.
echo  Fix it, then run setup.bat again; finished steps are skipped.
echo.
pause
exit /b 1
