@echo off
setlocal
title Signora Setup
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 (
    echo.
    echo Signora setup did not complete. Review the messages above.
)
echo.
pause
