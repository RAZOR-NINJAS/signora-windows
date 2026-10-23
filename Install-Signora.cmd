@echo off
setlocal EnableExtensions
title Signora Setup
cd /d "%~dp0"

echo "%~dp0" | findstr /i /c:"\AppData\Local\Temp\" /c:".zip" >nul
if not errorlevel 1 goto :inside_zip
if not exist "%~dp0install.ps1" goto :missing

powershell -NoProfile -Command "if (-not (Test-Path -LiteralPath '%~dp0install.ps1')) { exit 7 }" >nul 2>&1
if errorlevel 7 goto :inside_zip

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

:inside_zip
echo.
echo  This file is running from a temporary ZIP view, not a real folder.
echo  Nothing was installed.
echo.
echo  Extract the archive first:
echo    1. Close this window.
echo    2. Right-click the downloaded ZIP file.
echo    3. Choose "Extract All..." and pick a real folder, e.g. C:\Signora
echo    4. Run Install-Signora.cmd from that extracted folder.
echo.
pause
exit /b 1

:missing
echo.
echo  install.ps1 is missing next to this file.
echo  Extract the whole archive and keep its contents together.
echo.
pause
exit /b 1
