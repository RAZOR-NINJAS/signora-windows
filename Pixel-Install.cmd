@echo off
setlocal EnableExtensions
title SIGNORA // PIXEL INSTALLER
cd /d "%~dp0"
mode con: cols=78 lines=40 >nul 2>&1

if not exist "%~dp0setup-windows.ps1" (
    echo.
    echo  setup-windows.ps1 is missing. Extract the whole repository first.
    echo.
    pause
    exit /b 1
)

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
