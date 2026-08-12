@echo off
cd /d "%~dp0.."
powershell -ExecutionPolicy Bypass -File "%~dp0build-production-apk.ps1" %*
if errorlevel 1 (
    echo.
    echo BUILD FAILED.
    pause
    exit /b 1
)
pause
exit /b 0
