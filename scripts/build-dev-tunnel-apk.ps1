# Build release APK for device testing against Cloudflare tunnel backends on this PC.
#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

function Get-FlutterExe {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $localProps = Join-Path $projectRoot 'android\local.properties'
    if (Test-Path -LiteralPath $localProps) {
        foreach ($line in Get-Content -LiteralPath $localProps) {
            if ($line -match '^\s*flutter\.sdk=(.+)$') {
                $sdk = $Matches[1].Trim().Replace('\\', '\')
                $bat = Join-Path $sdk 'bin\flutter.bat'
                if (Test-Path -LiteralPath $bat) { return $bat }
            }
        }
    }

    $fallback = 'C:\flutter\bin\flutter.bat'
    if (Test-Path -LiteralPath $fallback) { return $fallback }

    throw 'Flutter SDK not found. Install to C:\flutter or add flutter to PATH.'
}

$flutter = Get-FlutterExe

$localProps = Join-Path $projectRoot 'android\local.properties'
if (Test-Path -LiteralPath $localProps) {
    foreach ($line in Get-Content -LiteralPath $localProps) {
        if ($line -match '^\s*sdk\.dir=(.+)$') {
            $sdkDir = $Matches[1].Trim().Replace('\\', '\')
            $env:ANDROID_HOME = $sdkDir
            $env:ANDROID_SDK_ROOT = $sdkDir
            break
        }
    }
}

Write-Host 'Building Attandance_App release APK (tunnel dev backends)...' -ForegroundColor Cyan
Write-Host '  AUTH/ERP:  https://hrm.peoplesitsolution.online'
Write-Host '  ZKTeco:    https://zktecolocal.peoplesitsolution.online'
Write-Host ''

& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $flutter build apk --release `
  --target-platform android-arm,android-arm64 `
  --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
if (Test-Path -LiteralPath $apk) {
  $sizeMb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
  Write-Host ''
  Write-Host "APK ready: $apk ($sizeMb MB)" -ForegroundColor Green
} else {
  Write-Host 'Build finished but APK not found at expected path.' -ForegroundColor Yellow
  exit 1
}
