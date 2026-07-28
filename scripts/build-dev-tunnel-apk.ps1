# Build lightweight release APKs (split-per-ABI) against Cloudflare tunnel backends.
# Default: phone ABIs (armeabi-v7a + arm64-v8a). Pass -Emulator for x86_64 AVD.
#Requires -Version 5.1
param(
    [switch]$Emulator
)

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

function Update-PubspecBuildNumber {
    $pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
    if (-not (Test-Path -LiteralPath $pubspecPath)) {
        throw "pubspec.yaml not found: $pubspecPath"
    }

    $content = Get-Content -LiteralPath $pubspecPath -Raw
    if ($content -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+(\d+)\s*$') {
        throw 'Could not parse version: X.Y.Z+N from pubspec.yaml'
    }

    $versionName = $Matches[1]
    $oldBuild = [int]$Matches[2]
    $newBuild = $oldBuild + 1
    $newLine = "version: $versionName+$newBuild"
    $updated = [regex]::Replace(
        $content,
        '(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+\d+\s*$',
        $newLine,
        1
    )
    Set-Content -LiteralPath $pubspecPath -Value $updated -NoNewline
    Write-Host "Build number: $oldBuild -> $newBuild (version $versionName+$newBuild)" -ForegroundColor Green
    return "$versionName+$newBuild"
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

$appVersion = Update-PubspecBuildNumber

$symbolsDir = Join-Path $projectRoot 'build\app\outputs\symbols'
New-Item -ItemType Directory -Force -Path $symbolsDir | Out-Null

if ($Emulator) {
    $platforms = 'android-x64'
    $expected = @('app-x86_64-release.apk')
    Write-Host 'Building Attandance_App release APK (tunnel, emulator x86_64)...' -ForegroundColor Cyan
} else {
    $platforms = 'android-arm,android-arm64'
    $expected = @('app-armeabi-v7a-release.apk', 'app-arm64-v8a-release.apk')
    Write-Host 'Building Attandance_App release APKs (tunnel, split-per-ABI phone)...' -ForegroundColor Cyan
}

Write-Host "  App version: $appVersion"
Write-Host '  AUTH/ERP:  https://hrm.peoplesitsolution.online'
Write-Host '  ZKTeco:    https://zktecolocal.peoplesitsolution.online'
Write-Host "  Platforms: $platforms"
Write-Host ''

& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $flutter build apk --release `
  --split-per-abi `
  --target-platform $platforms `
  --obfuscate `
  --split-debug-info=$symbolsDir `
  --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apkDir = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
Write-Host ''
$found = $false
foreach ($name in $expected) {
    $apk = Join-Path $apkDir $name
    if (Test-Path -LiteralPath $apk) {
        $sizeMb = [math]::Round((Get-Item -LiteralPath $apk).Length / 1MB, 1)
        Write-Host "APK ready: $apk ($sizeMb MB)" -ForegroundColor Green
        $found = $true
    } else {
        Write-Host "Expected APK missing: $apk" -ForegroundColor Yellow
    }
}

if (-not $found) {
    Write-Host 'Build finished but no expected split APKs were found.' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host "Built app version: $appVersion" -ForegroundColor Cyan
Write-Host 'Install tip: modern phones -> app-arm64-v8a-release.apk; 32-bit -> app-armeabi-v7a-release.apk; AVD -> use -Emulator.' -ForegroundColor DarkGray
