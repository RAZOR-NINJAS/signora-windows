@echo off
setlocal EnableExtensions
title Signora Setup
cd /d "%~dp0"

echo "%~dp0" | findstr /i /c:"\AppData\Local\Temp\" /c:".zip" >nul
if errorlevel 1 if exist "%~dp0install.ps1" goto :run_local

goto :bootstrap

:run_local
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" (
    echo Signora setup did not complete [exit %CODE%]. Review the messages above.
)
echo.
pause
exit /b %CODE%

:bootstrap
echo.
echo  Preparing Signora in your own user folder.
echo  Nothing else on this computer is touched.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;$dest=Join-Path $env:LOCALAPPDATA 'Signora\app';$zip=Join-Path $env:TEMP 'signora-windows.zip';$tmp=Join-Path $env:TEMP 'signora-download';New-Item -ItemType Directory -Force -Path $dest > $null;if(Test-Path $tmp){Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue};try{Invoke-WebRequest -Uri 'https://github.com/RAZOR-NINJAS/signora-windows/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing -ErrorAction Stop}catch{Write-Host '';Write-Host '  DOWNLOAD FAILED. Check the internet connection and run this file again.' -ForegroundColor Red;exit 2};Expand-Archive -Path $zip -DestinationPath $tmp -Force;$inner=Get-ChildItem -Path $tmp -Directory -ErrorAction Stop | Select-Object -First 1;Copy-Item -Path (Join-Path $inner.FullName '*') -Destination $dest -Recurse -Force;Write-Host '  Downloaded.' -ForegroundColor Green;Start-Process -FilePath (Join-Path $dest 'Install-Signora.cmd') -Wait"

set "CODE=%ERRORLEVEL%"
if not "%CODE%"=="0" (
    echo.
    echo  Could not prepare the files [exit %CODE%].
    echo  Check the internet connection, then run this file again.
    echo.
    pause
)
exit /b %CODE%
