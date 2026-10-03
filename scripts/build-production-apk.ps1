# Build lightweight release APKs (split-per-ABI) against live production backends.
# Default: phone ABIs (armeabi-v7a + arm64-v8a). Pass -Emulator for x86_64 AVD.
# Always increments build number (+N). Optional -UpdateLevel bumps marketing version:
#   Build  (default) — keep X.Y.Z, only +N
#   Minor  — X.Y.Z -> X.Y.(Z+1)   e.g. 2.2.1 -> 2.2.2
#   Medium — X.Y.Z -> X.(Y+1).Z   e.g. 2.2.1 -> 2.3.1
#   Major  — X.Y.Z -> (X+1).Y.Z   e.g. 2.2.1 -> 3.2.1
#
# -Channel beta builds against ota/beta/manifest.json and puts the build number
# in the 9000+ band, so a beta build is never offered to a production phone.
#Requires -Version 5.1
param(
    [switch]$Emulator,
    [switch]$Publish,
    [string]$ReleaseNotes = '',
    [ValidateSet('Build', 'Minor', 'Medium', 'Major')]
    [string]$UpdateLevel = 'Build',
    [ValidateSet('prod', 'beta')]
    [string]$Channel = 'prod'
)

$ErrorActionPreference = 'Stop'

# Disjoint version bands per channel. The app's update check is a plain integer
# compare, so a shared counter would let a beta publish reach production
# devices. Keep beta above this floor and prod below $ProdVersionCeiling.
$BetaVersionFloor = 9000
$ProdVersionCeiling = 8999

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
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [ValidateSet('prod', 'beta')]
        [string]$Channel,
        [int]$BetaVersionFloor = 9000,
        [int]$ProdVersionCeiling = 8999
    )

    $pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
    if (-not (Test-Path -LiteralPath $pubspecPath)) {
        throw "pubspec.yaml not found: $pubspecPath"
    }

    $content = Get-Content -LiteralPath $pubspecPath -Raw
    # X.Y.Z, an optional pre-release segment (-beta.1), then +BUILD.
    # The pre-release group is required for a beta channel: a beta
    # build bumped from 2.5.2-beta.1+9008 must stay a beta version,
    # not silently become 2.5.2.
    if ($content -notmatch '(?m)^version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)(-[0-9A-Za-z.]+)?\+(\d+)\s*$') {
        throw 'Could not parse version: X.Y.Z[+N] from pubspec.yaml'
    }

    $major = [int]$Matches[1]
    $medium = [int]$Matches[2]
    $minor = [int]$Matches[3]
    $oldPre = if ($Matches[4]) { $Matches[4] } else { '' }
    $oldBuild = [int]$Matches[5]
    $oldName = "$major.$medium.$minor"

    switch ($Level) {
        'Minor'  { $minor++ }
        'Medium' { $medium++ }
        'Major'  { $major++ }
        'Build'  { }
    }

    # The band is applied AFTER the marketing-version bump, and is independent
    # of it: a beta build is 2.6.0-beta.1 at 9001, not "the next number". The
    # next build in the same channel is 9002 and keeps the version name.
    $newBuild = $oldBuild + 1

    if ($Channel -eq 'beta' -and $newBuild -lt $BetaVersionFloor) {
        # Count up to the floor rather than jumping blindly to it, so successive
        # beta builds stay consecutive and a tester can tell which is newer.
        $newBuild = $BetaVersionFloor + ($newBuild % 100)
        Write-Host "Beta band: build number raised to $newBuild (floor $BetaVersionFloor)" -ForegroundColor Yellow
    }
    if ($Channel -eq 'prod' -and $newBuild -gt $ProdVersionCeiling) {
        throw "Prod build number $newBuild is inside the beta band (<= $ProdVersionCeiling is required for prod)."
    }

    # Preserve the pre-release segment when the marketing version did
    # not change, so bumping 2.5.2-beta.1+9008 does not reset it.
    $newName = "$major.$medium.$minor"
    if ($Channel -eq 'beta') {
        $newName = if ($oldPre -and $oldName -eq "$major.$medium.$minor") {
            "$major.$medium.$minor$oldPre"
        } else {
            "$major.$medium.$minor-beta.1"
        }
    }

    $newLine = "version: $newName+$newBuild"
    $updated = [regex]::Replace(
        $content,
        '(?m)^version:\s*[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?\+\d+\s*$',
        $newLine,
        1
    )
    Set-Content -LiteralPath $pubspecPath -Value $updated -NoNewline

    if ($oldName -ne $newName) {
        Write-Host "Marketing version: $oldName -> $newName" -ForegroundColor Green
    } else {
        Write-Host "Marketing version: $newName (unchanged; UpdateLevel=$Level)" -ForegroundColor DarkGray
    }
    Write-Host "Build number: $oldBuild -> $newBuild (version $newName+$newBuild, channel $Channel)" -ForegroundColor Green
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

$appVersion = Update-PubspecVersion -Level $UpdateLevel -Channel $Channel -BetaVersionFloor $BetaVersionFloor -ProdVersionCeiling $ProdVersionCeiling

$rocketLauncherEnv = Join-Path (Split-Path $projectRoot -Parent) 'rocket launcher\config\github.env'
$config = @{}
if (Test-Path -LiteralPath $rocketLauncherEnv) {
    foreach ($line in Get-Content -LiteralPath $rocketLauncherEnv) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        if ($trimmed -match '^([^=]+)=(.*)$') {
            $config[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
}

# The manifest URL is derived from the channel, not read from the flat
# UPDATE_MANIFEST_URL key. That key is a single prod-only URL, so a beta build
# reading it would check the production manifest and be offered a production
# APK over the beta build under test.
$otaBase = if ($config.OTA_BASE_URL) {
    $config.OTA_BASE_URL.TrimEnd('/')
} else {
    $owner = if ($config.GITHUB_OWNER) { $config.GITHUB_OWNER } else { 'ciphercall' }
    $repo = if ($config.GITHUB_REPO) { $config.GITHUB_REPO } else { 'rocket-launcher' }
    $branch = if ($config.GITHUB_BRANCH) { $config.GITHUB_BRANCH } else { 'main' }
    "https://raw.githubusercontent.com/$owner/$repo/$branch"
}

$updateManifestUrl = if ($Channel -eq 'beta') {
    "$otaBase/ota/beta/manifest.json"
} else {
    "$otaBase/ota/manifest.json"
}

$dartDefines = @(
    "UPDATE_CHANNEL=$Channel",
    "UPDATE_MANIFEST_URL=$updateManifestUrl"
)
Write-Host "  Channel: $Channel"
Write-Host "  OTA manifest: $updateManifestUrl" -ForegroundColor DarkGray

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
    # Beta gets its own inbox, matching publish-update.ps1's default. Sharing one
    # would let a beta build sit in the inbox and be picked up by the next prod
    # publish, which copies the same two filenames.
    $channelSuffix = if ($Channel -eq 'beta') { 'beta\' } else { '' }
    $inboxDir = Join-Path (Split-Path $projectRoot -Parent) "rocket launcher\inbox\$channelSuffix"
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
        Write-Host "Publishing [$Channel] to GitHub via Rocket Launcher..." -ForegroundColor Cyan
        $notes = if ($ReleaseNotes) { $ReleaseNotes } else { "Build $appVersion" }
        & powershell -ExecutionPolicy Bypass -File $publishScript -ReleaseNotes $notes -Channel $Channel
    } else {
        Write-Host "Publish requested but script not found: $publishScript" -ForegroundColor Yellow
    }
}
