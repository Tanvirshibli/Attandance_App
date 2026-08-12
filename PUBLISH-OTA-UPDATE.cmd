@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

echo ========================================
echo  PPHL Attendance - Publish OTA Update
echo ========================================
echo.
echo This will:
echo   1. Bump the build number
echo   2. Compile release APKs (arm + arm64)
echo   3. Upload to GitHub Releases
echo   4. Update the OTA manifest for all users
echo.

set "RELEASE_NOTES="
set /p RELEASE_NOTES="Release notes (optional, press Enter for default): "
if "!RELEASE_NOTES!"=="" set "RELEASE_NOTES=App update"

echo.
powershell -ExecutionPolicy Bypass -File "%~dp0scripts\build-production-apk.ps1" -Publish -ReleaseNotes "!RELEASE_NOTES!"
if errorlevel 1 (
    echo.
    echo OTA PUBLISH FAILED.
    pause
    exit /b 1
)

echo.
echo ========================================
echo  OTA update is live for users!
echo ========================================
set "ENV_FILE=%~dp0..\rocket launcher\config\github.env"
if exist "!ENV_FILE!" (
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /b "UPDATE_MANIFEST_URL=" "!ENV_FILE!" 2^>nul`) do echo   Manifest: %%B
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /b "GITHUB_OWNER=" "!ENV_FILE!" 2^>nul`) do set "GH_OWNER=%%B"
    for /f "usebackq tokens=1,* delims==" %%A in (`findstr /b "GITHUB_REPO=" "!ENV_FILE!" 2^>nul`) do set "GH_REPO=%%B"
    if defined GH_OWNER if defined GH_REPO echo   Releases: https://github.com/!GH_OWNER!/!GH_REPO!/releases/latest
)
echo.
pause
exit /b 0
