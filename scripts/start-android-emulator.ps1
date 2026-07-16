# Start the Pixel_6_API_35 Android Emulator and wait until adb + internet work.
#Requires -Version 5.1
param(
    [switch]$ColdBoot
)

$ErrorActionPreference = 'Stop'

$AvdName = 'Pixel_6_API_35'
$DnsServers = '8.8.8.8,1.1.1.1'
$SdkRoot = $env:ANDROID_SDK_ROOT
if (-not $SdkRoot) { $SdkRoot = $env:ANDROID_HOME }
if (-not $SdkRoot) { $SdkRoot = Join-Path $env:LOCALAPPDATA 'Android\sdk' }
if (-not (Test-Path -LiteralPath $SdkRoot)) {
    throw "Android SDK not found. Set ANDROID_SDK_ROOT or install the SDK under $env:LOCALAPPDATA\Android\sdk"
}

$emulator = Join-Path $SdkRoot 'emulator\emulator.exe'
$adb = Join-Path $SdkRoot 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $emulator)) {
    throw "Android Emulator not installed at $emulator. Run sdkmanager emulator."
}
if (-not (Test-Path -LiteralPath $adb)) {
    throw "adb not found at $adb"
}

$env:ANDROID_HOME = $SdkRoot
$env:ANDROID_SDK_ROOT = $SdkRoot

$avds = & $emulator -list-avds 2>&1
if ($avds -notcontains $AvdName) {
    throw "AVD '$AvdName' not found. Available: $($avds -join ', ')"
}

function Get-EmulatorSerial {
    $lines = & $adb devices 2>&1
    $match = $lines | Where-Object { $_ -match '^(emulator-\d+)\s+device$' } | Select-Object -First 1
    if ($match -and ($match -match '^(emulator-\d+)')) {
        return $Matches[1]
    }
    return $null
}

function Disable-EmulatorPrivateDns {
    param([string]$Serial)

    try {
        & $adb -s $Serial shell settings put global private_dns_mode off 2>$null | Out-Null
        & $adb -s $Serial shell settings delete global private_dns_specifier 2>$null | Out-Null
        Write-Host 'Disabled Private DNS on emulator (can block outbound HTTPS).'
    } catch {
        Write-Host 'Could not change Private DNS settings (continuing).'
    }
}

function Test-EmulatorInternet {
    param([string]$Serial)

    if (-not $Serial) { return $false }

    # Prefer production HRM host (same target as login). Avoid relying only on 8.8.8.8 -
    # some networks drop ICMP to public DNS even when HTTPS works.
    $targets = @(
        'hrm.peoplesitsolution.com',
        '8.8.8.8',
        '1.1.1.1'
    )

    foreach ($target in $targets) {
        $pingOut = ''
        try {
            $pingOut = (& $adb -s $Serial shell ping -c 1 -W 4 $target 2>&1 | Out-String)
        } catch {
            $pingOut = $_.Exception.Message
        }

        if ($pingOut -match '1 packets transmitted[\s\S]*1 (packets )?received|1 received') {
            Write-Host "  ping $target OK"
            return $true
        }
    }

    return $false
}

function Stop-EmulatorInstances {
    Write-Host 'Stopping existing emulator instance(s)...'
    try {
        & $adb emu kill 2>$null | Out-Null
    } catch {
        # ignore
    }

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $still = Get-EmulatorSerial
        if (-not $still) { break }
        Start-Sleep -Seconds 2
    }

    Get-Process -Name 'qemu-system-x86_64', 'emulator', 'emulator-crash-service' -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
}

function Start-AvdProcess {
    param([switch]$ForceColdBoot)

    $emuArgs = @(
        '-avd', $AvdName,
        '-dns-server', $DnsServers,
        '-netdelay', 'none',
        '-netspeed', 'full'
    )
    if ($ForceColdBoot -or $ColdBoot) {
        $emuArgs += '-no-snapshot-load'
        Write-Host "Cold-booting AVD: $AvdName (DNS=$DnsServers)"
    } else {
        Write-Host "Starting AVD: $AvdName (DNS=$DnsServers)"
    }

    Start-Process -FilePath $emulator -ArgumentList $emuArgs -WindowStyle Normal
}

function Wait-EmulatorBoot {
    Write-Host 'Waiting for emulator to appear in adb...'
    $deadline = (Get-Date).AddMinutes(5)
    $serial = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $lines = & $adb devices 2>&1
        $match = $lines | Where-Object { $_ -match '^(emulator-\d+)\s+(device|offline|unauthorized)' } |
            ForEach-Object {
                if ($_ -match '^(emulator-\d+)\s+(\S+)') {
                    [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
                }
            } | Select-Object -First 1
        if ($match) {
            $serial = $match.Serial
            if ($match.State -eq 'device') { break }
            Write-Host "  $($match.Serial) is $($match.State)..."
        } else {
            Write-Host '  waiting for emulator...'
        }
    }

    if (-not $serial) {
        throw 'Timed out waiting for emulator to register with adb.'
    }

    Write-Host "Waiting for boot completed on $serial..."
    $deadline = (Get-Date).AddMinutes(8)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3

        $stateLine = (& $adb devices 2>&1 | Where-Object { $_ -match "^$([regex]::Escape($serial))\s+" } | Select-Object -First 1)
        if (-not $stateLine -or $stateLine -notmatch '\s+device$') {
            Write-Host "  $serial not fully online yet..."
            continue
        }

        $boot = ''
        try {
            $boot = (& $adb -s $serial shell getprop sys.boot_completed 2>$null | Out-String).Trim()
        } catch {
            Write-Host '  getprop failed (device still starting)...'
            continue
        }

        if ($boot -eq '1') {
            return $serial
        }
        Write-Host '  still booting...'
    }

    throw "Timed out waiting for $serial to finish booting."
}

function Wait-EmulatorInternet {
    param([string]$Serial)

    Write-Host "Checking internet on $Serial..."
    $deadline = (Get-Date).AddMinutes(2)
    while ((Get-Date) -lt $deadline) {
        if (Test-EmulatorInternet -Serial $Serial) {
            Write-Host "Internet OK on $Serial (DNS=$DnsServers)."
            return $true
        }
        Write-Host '  network not ready yet...'
        Start-Sleep -Seconds 5
    }
    return $false
}

# If already online with working internet, keep it
$existing = Get-EmulatorSerial
if ($existing -and -not $ColdBoot) {
    Disable-EmulatorPrivateDns -Serial $existing
    if (Test-EmulatorInternet -Serial $existing) {
        Write-Host "Emulator already online with working internet:"
        Write-Host "  $existing	device"
        exit 0
    }

    Write-Host "Emulator $existing is online but has no internet - restarting with DNS fix..."
    Stop-EmulatorInstances
    Start-AvdProcess -ForceColdBoot
} elseif ($existing -and $ColdBoot) {
    Stop-EmulatorInstances
    Start-AvdProcess -ForceColdBoot
} else {
    Start-AvdProcess
}

$serial = Wait-EmulatorBoot
Write-Host "Emulator $serial is ready (booted)."
Disable-EmulatorPrivateDns -Serial $serial

if (-not (Wait-EmulatorInternet -Serial $serial)) {
    # One automatic cold-boot retry if we did not already cold-boot
    if (-not $ColdBoot) {
        Write-Host 'Internet still down - cold-booting once more with explicit DNS...'
        Stop-EmulatorInstances
        Start-AvdProcess -ForceColdBoot
        $serial = Wait-EmulatorBoot
        Disable-EmulatorPrivateDns -Serial $serial
        if (Wait-EmulatorInternet -Serial $serial) {
            Write-Host "Emulator $serial is ready."
            exit 0
        }
    }

    Write-Host "WARNING: Emulator $serial booted but cannot reach the internet."
    Write-Host "  Login to https://hrm.peoplesitsolution.com will time out until this is fixed."
    Write-Host "  Try: powershell -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1 -ColdBoot"
    Write-Host "  Verify: adb shell ping -c 2 8.8.8.8"
    Write-Host "  Verify: adb shell ping -c 2 hrm.peoplesitsolution.com"
    exit 2
}

Write-Host "Emulator $serial is ready."
exit 0
