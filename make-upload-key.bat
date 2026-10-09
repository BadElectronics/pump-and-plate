@echo off
setlocal EnableExtensions
title Pump and Plate: make the Google Play upload key
cd /d "%~dp0"
call "%~dp0scripts\env.bat"

rem Makes the key that signs every Google Play upload, once, and keeps it in
rem the keys folder (never uploaded to GitHub). Then copies the two values the
rem cloud build needs, one at a time, so you can paste them into GitHub.

set "KEYS=%ROOT%\keys"
set "JKS=%KEYS%\upload-keystore.jks"
set "PWFILE=%KEYS%\upload-key-password.txt"

if not exist "%JAVA_HOME%\bin\keytool.exe" (
  echo [!] Java isn't installed in the tools folder yet. Run setup.bat first.
  goto :fail
)
if not exist "%KEYS%" mkdir "%KEYS%"

if exist "%JKS%" (
  echo The upload key already exists in keys\upload-keystore.jks, so it was kept.
  if not exist "%PWFILE%" (
    echo [!] Its password file keys\upload-key-password.txt is missing.
    goto :fail
  )
  goto :copy
)

rem A long random password, saved next to the key.
powershell -NoProfile -Command "$b = New-Object byte[] 24; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [IO.File]::WriteAllText($env:PWFILE, ([Convert]::ToBase64String($b) -replace '[+/=]',''))"
if errorlevel 1 goto :fail
set /p STOREPW=<"%PWFILE%"

"%JAVA_HOME%\bin\keytool.exe" -genkeypair -keystore "%JKS%" -storetype PKCS12 -alias upload -keyalg RSA -keysize 2048 -validity 10000 -storepass "%STOREPW%" -keypass "%STOREPW%" -dname "CN=Luch Electronics LLC, O=Luch Electronics LLC, C=US"
if errorlevel 1 goto :fail
echo.
echo Made the upload key: keys\upload-keystore.jks
echo Its password is in:  keys\upload-key-password.txt

:copy
echo.
echo ============================================================
echo  Back up the keys folder now (a USB stick or password manager).
echo  If the key is lost, Google has to reset it, which takes days.
echo ============================================================
echo.
echo Open this page in your browser:
echo   https://github.com/BadElectronics/pump-and-plate/settings/secrets/actions/new
echo.
powershell -NoProfile -Command "Set-Clipboard -Value ([Convert]::ToBase64String([IO.File]::ReadAllBytes($env:JKS)))"
if errorlevel 1 goto :fail
echo SECRET 1 is now copied.
echo   Name:   ANDROID_KEYSTORE_BASE64
echo   Secret: paste (Ctrl+V), then click "Add secret".
echo.
echo Then click "New repository secret" for the next one.
pause
powershell -NoProfile -Command "Set-Clipboard -Value ((Get-Content -Raw $env:PWFILE).Trim())"
if errorlevel 1 goto :fail
echo.
echo SECRET 2 is now copied.
echo   Name:   ANDROID_KEYSTORE_PASSWORD
echo   Secret: paste (Ctrl+V), then click "Add secret".
echo.
echo Done. The next cloud build makes a Google Play file signed with this key.
pause
exit /b 0

:fail
echo.
echo Nothing was copied. The message above says what went wrong.
pause
exit /b 1
