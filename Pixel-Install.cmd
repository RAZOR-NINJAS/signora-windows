@echo off
setlocal EnableExtensions
title SIGNORA // PIXEL INSTALLER
cd /d "%~dp0"

rem Fast path: a real extracted folder with the script next to this file.
echo "%~dp0" | findstr /i /c:"\AppData\Local\Temp\" /c:".zip" >nul
if errorlevel 1 if exist "%~dp0setup-windows.ps1" goto :run_local

rem Windows runs files inside a ZIP from a temporary folder that disappears.
rem Instead of asking the user to extract anything, fetch a clean copy.
goto :bootstrap

:run_local
if exist "%~dp0install-error.log" del /q "%~dp0install-error.log" >nul 2>&1

mode con: cols=78 lines=40 >nul 2>&1

rem Files from a downloaded ZIP carry the Mark-of-the-Web, which makes the
rem execution policy reject unsigned scripts. Clear it before running.
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" -Pixel %*
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" goto :failed

echo  Signora is installed and starting now.
echo  You can close this window.
echo.
pause
exit /b 0

:failed
echo  ============================================================
echo   INSTALL FAILED  [exit %CODE%]
echo  ============================================================
if not exist "%~dp0install-error.log" goto :no_log
echo.
type "%~dp0install-error.log"
goto :stop

:no_log
echo.
echo  No error log was written, so PowerShell may have refused to run.
echo  Open PowerShell in this folder and run:
echo      Get-ChildItem -Recurse ^| Unblock-File
echo      powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-windows.ps1 -Pixel

:stop
echo.
pause
exit /b %CODE%

:bootstrap
echo.
echo  Preparing Signora in your own user folder.
echo  Nothing else on this computer is touched.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$dest=Join-Path $env:LOCALAPPDATA 'Signora\app';$zip=Join-Path $env:TEMP 'signora-windows.zip';$tmp=Join-Path $env:TEMP 'signora-download';New-Item -ItemType Directory -Force -Path $dest > $null;if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue};try{Invoke-WebRequest -Uri 'https://github.com/RAZOR-NINJAS/signora-windows/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop}catch{Write-Host '';Write-Host '  DOWNLOAD FAILED. Check the internet connection and run this file again.' -ForegroundColor Red;exit 2};Expand-Archive -Path $zip -DestinationPath $tmp -Force;$inner=Get-ChildItem -Path $tmp -Directory -ErrorAction Stop | Select-Object -First 1;Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $dest -Recurse -Force;Write-Host '  Downloaded.' -ForegroundColor Green;Start-Process -FilePath (Join-Path $dest 'Pixel-Install.cmd') -Wait"

set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
    echo.
    echo  Could not prepare the files [exit %CODE%].
    echo  Check the internet connection, then run this file again.
    echo.
    pause
)
exit /b %CODE%
