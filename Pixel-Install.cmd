@echo off
setlocal EnableExtensions
title SIGNORA // PIXEL INSTALLER
cd /d "%~dp0"

rem Explorer's ZIP preview runs files out of %TEMP%, and that folder can vanish
rem before PowerShell reads the script. Refuse it with a readable message.
echo "%~dp0" | findstr /i /c:"\AppData\Local\Temp\" /c:".zip" >nul
if not errorlevel 1 goto :inside_zip
if not exist "%~dp0setup-windows.ps1" goto :missing

powershell -NoProfile -Command "if (-not (Test-Path -LiteralPath '%~dp0setup-windows.ps1')) { exit 7 }" >nul 2>&1
if errorlevel 7 goto :inside_zip

mode con: cols=78 lines=40 >nul 2>&1
if exist "%~dp0install-error.log" del /q "%~dp0install-error.log" >nul 2>&1

rem Files from a downloaded ZIP carry the Mark-of-the-Web, which makes the
rem execution policy reject unsigned scripts. Clear it before running.
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse -Include *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" -Pixel %*
set "CODE=%ERRORLEVEL%"

echo.
if not "%CODE%"=="0" goto :failed

echo  Install complete.
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

:inside_zip
echo.
echo  This file is running from a temporary ZIP view, not a real folder.
echo  Nothing was installed.
echo.
echo  Extract the archive first:
echo    1. Close this window.
echo    2. Right-click the downloaded ZIP file.
echo    3. Choose "Extract All..." and pick a real folder, e.g. C:\Signora
echo    4. Run Pixel-Install.cmd from that extracted folder.
echo.
pause
exit /b 1

:missing
echo.
echo  setup-windows.ps1 is missing next to this file.
echo  Extract the whole archive and keep its contents together.
echo.
pause
exit /b 1
