# Cloudflare Tunnel Development — Attandance_App

Last updated: July 2, 2026

## Overview

During development, the mobile app talks to local Docker stacks **only through Cloudflare named tunnels**. Production builds use different hostnames and require no tunnel flag.

```
Phone (any network)
  --HTTPS--> Cloudflare Edge
  --tunnel--> cloudflared Windows service (this PC)
  --HTTP--> localhost Docker stack
```

## This PC — Docker stacks and tunnels

| Docker stack | Windows service | Profile dir | Public hostname | Local origin |
|--------------|-----------------|-------------|-----------------|--------------|
| `hrm-production` | `Cloudflared-hrmlocal` | `%ProgramData%\cloudflared\hrmlocal\` | `https://hrm.peoplesitsolution.online` | `http://localhost:8020` |
| `hrm-frontend-production` | `Cloudflared-hrmfrontlocal` | `%ProgramData%\cloudflared\hrmfrontlocal\` | `https://hrmfrontlocal.peoplesitsolution.online` | `http://localhost:8021` |
| `zkteco-production` | `Cloudflared-zktecolocal` | `%ProgramData%\cloudflared\zktecolocal\` | `https://zktecolocal.peoplesitsolution.online` | `http://localhost:8095` |

Cloudflare Zero Trust dashboard tunnels (this machine): `hrm local`, `hrmfront local`, `zkteco local`.

Each service runs `cloudflared tunnel run --token <token>` via `run-service.cmd` under its profile folder. Tokens and hostnames are saved in:

- `tunnel.token`
- `tunnel.hostname`
- `tunnel.local-url`
- `tunnel.name`

Install/repair tunnels from deployment folders:

- HRM: `hrm_deployment\docker\INSTALL-TUNNEL.bat`
- HRM frontend: `hrm_frontend_deployment\docker\INSTALL-TUNNEL.bat`
- ZKTeco: `zkteco_deployment\docker\INSTALL-TUNNEL.bat`

Verify services:

```powershell
Get-CimInstance Win32_Service | Where-Object { $_.Name -like 'Cloudflared*' } | Select-Object Name, State
```

## App backend mapping (dev vs production)

| Feature | Dev tunnel build | Production build |
|---------|------------------|------------------|
| Login, profile, logout | `https://hrm.peoplesitsolution.online` | `https://hrm.peoplesitsolution.com` |
| Face registration | `https://hrm.peoplesitsolution.online` | `https://hrm.peoplesitsolution.com` |
| Future ERP (leave, holiday, sales, payment) | `https://hrm.peoplesitsolution.online` | `https://hrm.peoplesitsolution.com` |
| Attendance list + check-in/out | `https://zktecolocal.peoplesitsolution.online` | `https://zkteco.peoplesitsolution.online` |

Configuration: `lib/config/app_config.dart` — controlled by `--dart-define=USE_LOCAL_TUNNEL_BACKENDS=true`.

The HRM frontend tunnel is **not** used by the mobile app; it is for browser/Vite testing only.

## Build dev APK for phone testing

From `Attandance_App` — produces **split-per-ABI** APKs (arm + arm64):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
```

Emulator x86_64:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -Emulator
```

Or manually:

```powershell
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true
```

Outputs: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk`

## Production APK (no tunnel)

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols
```

Only change URLs for production by **omitting** `USE_LOCAL_TUNNEL_BACKENDS` (defaults in `app_config.dart`).

## Pre-install checklist

1. Docker stacks `hrm-production`, `zkteco-production` are running.
2. Cloudflared services `Cloudflared-hrmlocal` and `Cloudflared-zktecolocal` show **RUNNING**.
3. Tunnel health in Cloudflare Zero Trust dashboard is **Healthy**.
4. Quick smoke test from this PC:

```powershell
Invoke-WebRequest -Uri "https://hrm.peoplesitsolution.online/login" -UseBasicParsing
Invoke-WebRequest -Uri "https://zktecolocal.peoplesitsolution.online/login" -UseBasicParsing
```

## Optional overrides

| Dart define | Purpose |
|-------------|---------|
| `USE_LOCAL_TUNNEL_BACKENDS=true` | Switch to tunnel hostnames above |
| `AUTH_API_BASE_URL` | Override HRM/ERP base only |
| `ATTENDANCE_API_BASE_URL` | Override ZKTeco base only |
| `API_BASE_URL` | Legacy alias for auth/ERP base |

## Related docs

- Workspace: [CLOUDFLARE_TUNNEL.md](../../CLOUDFLARE_TUNNEL.md)
- HRM tunnel: [hrm_deployment/docker/cloudflare-tunnel-kit/docs/HRM_TUNNEL_SETUP.md](../../hrm_deployment/docker/cloudflare-tunnel-kit/docs/HRM_TUNNEL_SETUP.md)
- ZKTeco tunnel: [zkteco_deployment/docker/cloudflare-tunnel-kit/docs/ZKTECO_TUNNEL_SETUP.md](../../zkteco_deployment/docker/cloudflare-tunnel-kit/docs/ZKTECO_TUNNEL_SETUP.md)
