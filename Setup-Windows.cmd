@echo off
setlocal
title Signora Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" %*
if errorlevel 1 (
    echo.
    echo Signora setup did not complete. Review the messages above.
    pause
    exit /b 1
)
echo.
pause
