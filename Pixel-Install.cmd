@echo off
setlocal
title SIGNORA // PIXEL INSTALLER
mode con: cols=78 lines=40 >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" -Pixel %*
if errorlevel 1 (
    echo.
    echo  GAME OVER. Review the errors above and run it again.
    pause
    exit /b 1
)
echo.
pause
