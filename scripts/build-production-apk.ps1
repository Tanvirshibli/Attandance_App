# Build lightweight release APKs (split-per-ABI) against live production backends.
# Default: phone ABIs (armeabi-v7a + arm64-v8a). Pass -Emulator for x86_64 AVD.
# Always increments build number (+N). Optional -UpdateLevel bumps marketing version:
#   Build  (default) — keep X.Y.Z, only +N
#   Minor  — X.Y.Z -> X.Y.(Z+1)   e.g. 2.2.1 -> 2.2.2
#   Medium — X.Y.Z -> X.(Y+1).Z   e.g. 2.2.1 -> 2.3.1
#   Major  — X.Y.Z -> (X+1).Y.Z   e.g. 2.2.1 -> 3.2.1
#Requires -Version 5.1
param(
    [switch]$Emulator,
    [switch]$Publish,
    [string]$ReleaseNotes = '',
    [ValidateSet('Build', 'Minor', 'Medium', 'Major')]
    [string]$UpdateLevel = 'Build'
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

function Update-PubspecVersion {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Build', 'Minor', 'Medium', 'Major')]
        [string]$Level
    )

    $pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
    if (-not (Test-Path -LiteralPath $pubspecPath)) {
        throw "pubspec.yaml not found: $pubspecPath"
    }

    $content = Get-Content -LiteralPath $pubspecPath -Raw
    if ($content -notmatch '(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)\+(\d+)\s*$') {
        throw 'Could not parse version: X.Y.Z+N from pubspec.yaml'
    }

    $major = [int]$Matches[1]
    $medium = [int]$Matches[2]
    $minor = [int]$Matches[3]
    $oldBuild = [int]$Matches[4]
    $oldName = "$major.$medium.$minor"

    switch ($Level) {
        'Minor'  { $minor++ }
        'Medium' { $medium++ }
        'Major'  { $major++ }
        'Build'  { }
    }

    $newName = "$major.$medium.$minor"
    $newBuild = $oldBuild + 1
    $newLine = "version: $newName+$newBuild"
    $updated = [regex]::Replace(
        $content,
        '(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+\d+\s*$',
        $newLine,
        1
    )
    Set-Content -LiteralPath $pubspecPath -Value $updated -NoNewline

    if ($oldName -ne $newName) {
        Write-Host "Marketing version ($Level): $oldName -> $newName" -ForegroundColor Green
    } else {
        Write-Host "Marketing version: $newName (unchanged; UpdateLevel=Build)" -ForegroundColor DarkGray
    }
    Write-Host "Build number: $oldBuild -> $newBuild (version $newName+$newBuild)" -ForegroundColor Green
    return "$newName+$newBuild"
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

$appVersion = Update-PubspecVersion -Level $UpdateLevel

$rocketLauncherEnv = Join-Path (Split-Path $projectRoot -Parent) 'rocket launcher\config\github.env'
$updateManifestUrl = $null
if (Test-Path -LiteralPath $rocketLauncherEnv) {
    foreach ($line in Get-Content -LiteralPath $rocketLauncherEnv) {
        if ($line -match '^\s*UPDATE_MANIFEST_URL=(.+)$') {
            $updateManifestUrl = $Matches[1].Trim()
            break
        }
    }
}

$dartDefines = @()
if ($updateManifestUrl) {
    $dartDefines += "UPDATE_MANIFEST_URL=$updateManifestUrl"
    Write-Host "  OTA manifest: $updateManifestUrl" -ForegroundColor DarkGray
} else {
    Write-Host '  OTA manifest: (default placeholder - set UPDATE_MANIFEST_URL in rocket launcher\config\github.env)' -ForegroundColor Yellow
}

$symbolsDir = Join-Path $projectRoot 'build\app\outputs\symbols'
New-Item -ItemType Directory -Force -Path $symbolsDir | Out-Null

if ($Emulator) {
    $platforms = 'android-x64'
    $expected = @('app-x86_64-release.apk')
    Write-Host 'Building Attandance_App release APK (production, emulator x86_64)...' -ForegroundColor Cyan
} else {
    $platforms = 'android-arm,android-arm64'
    $expected = @('app-armeabi-v7a-release.apk', 'app-arm64-v8a-release.apk')
    Write-Host 'Building Attandance_App release APKs (production, split-per-ABI phone)...' -ForegroundColor Cyan
}

Write-Host "  App version: $appVersion"
Write-Host "  UpdateLevel: $UpdateLevel"
Write-Host '  AUTH/ERP:  https://hrm.peoplesitsolution.com'
Write-Host '  ZKTeco:    https://zkteco.peoplesitsolution.online'
Write-Host "  Platforms: $platforms"
Write-Host ''

& $flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$buildArgs = @(
    'build', 'apk', '--release',
    '--split-per-abi',
    '--target-platform', $platforms,
    '--no-tree-shake-icons',
    '--obfuscate',
    "--split-debug-info=$symbolsDir"
)
foreach ($define in $dartDefines) {
    $buildArgs += '--dart-define'
    $buildArgs += $define
}

& $flutter @buildArgs

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
Write-Host 'For local Cloudflare tunnel backends use scripts/build-dev-tunnel-apk.ps1 instead.' -ForegroundColor DarkGray

if ($Publish) {
    $inboxDir = Join-Path (Split-Path $projectRoot -Parent) 'rocket launcher\inbox'
    New-Item -ItemType Directory -Force -Path $inboxDir | Out-Null
    foreach ($name in $expected) {
        $src = Join-Path $apkDir $name
        if (Test-Path -LiteralPath $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $inboxDir $name) -Force
        }
    }
    $publishScript = Join-Path (Split-Path $projectRoot -Parent) 'rocket launcher\scripts\publish-update.ps1'
    if (Test-Path -LiteralPath $publishScript) {
        Write-Host ''
        Write-Host 'Publishing to GitHub via Rocket Launcher...' -ForegroundColor Cyan
        $notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Build $appVersion" }
        & powershell -ExecutionPolicy Bypass -File $publishScript -ReleaseNotes $notes
    } else {
        Write-Host "Publish requested but script not found: $publishScript" -ForegroundColor Yellow
    }
}
