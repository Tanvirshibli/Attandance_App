# employee_attendance

Flutter Android app for PPHL attendance.

## Current integration scope

- Login/auth session: JWT on `pphl_erp`
- Face registration: JWT on `pphl_erp` → `face_registration_android`
- Check-in/check-out + attendance history: public API on `zkteco-Automation-management-PPHL` (no JWT; `employee_id` required) with HRM JWT mobile attendance preferred when logged in
- **Employee services (v2.2.0):** footer **Services** tab (Attendance Report, Leave, Payments hub, Sales Info with live person-sales report + Post sale/booking (feed/chicks → booking API; other modules → sales-person-sales) with dealer dropdowns, Vehicles, **Farm & Dealer** field collection, Geo Tracking). Auth-wise receive uses live setup lists; HRM payments remain demo by default; see [docs/SALES_AND_PAYMENTS_API_CONTRACT.md](docs/SALES_AND_PAYMENTS_API_CONTRACT.md) and [docs/FARM_DEALER_MOBILE.md](docs/FARM_DEALER_MOBILE.md)
- Home / Attendance KPIs driven from live punches + HRM summary (Alerts empty until a notifications API exists)
- JWT refresh on 401 (single-flight); profile cache for geo; 429 pauses geo HRM work — see [docs/AUTH_AND_RATE_LIMITS.md](docs/AUTH_AND_RATE_LIMITS.md)
- Geo: live OpenStreetMap window, 5-min foreground timer, WorkManager, ongoing notification; FCM wake registers tokens and handles `geo_wake` data pushes when `android/app/google-services.json` is present (see `.example`)
- Persistent per-install device identity sent with attendance and face-registration requests

See [docs/MOBILE_EMPLOYEE_FEATURES.md](docs/MOBILE_EMPLOYEE_FEATURES.md) for API wiring status per feature. Farm & Dealer mobile API: [docs/FARM_DEALER_MOBILE.md](docs/FARM_DEALER_MOBILE.md). Backend handoff for Sales/Payments: [docs/SALES_AND_PAYMENTS_API_CONTRACT.md](docs/SALES_AND_PAYMENTS_API_CONTRACT.md). Emulator workflow: [docs/EMULATOR_TESTING.md](docs/EMULATOR_TESTING.md). Rate limits / forced logout: [docs/AUTH_AND_RATE_LIMITS.md](docs/AUTH_AND_RATE_LIMITS.md).

## Backend split

| Feature | Backend | Auth |
|---------|---------|------|
| Login, profile, logout, face registration, future ERP modules | `pphl_erp` | JWT |
| Attendance list + check-in/out | `zkteco-Automation-management-PPHL` | None + `employee_id` |

### Production URLs (default APK)

| Backend | URL |
|---------|-----|
| HRM / ERP | `https://hrm.peoplesitsolution.com` |
| ZKTeco attendance | `https://zkteco.peoplesitsolution.online` |

### Development URLs (Cloudflare tunnel on dev PC)

| Backend | URL | Docker stack |
|---------|-----|--------------|
| HRM / ERP | `https://hrm.peoplesitsolution.online` | `hrm-production` (:8020) |
| ZKTeco attendance | `https://zktecolocal.peoplesitsolution.online` | `zkteco-production` (:8095) |

See [docs/TUNNEL_DEVELOPMENT.md](docs/TUNNEL_DEVELOPMENT.md) for Windows services, tunnel profiles, and verification steps.

### pphl_erp (JWT)

- `POST /api/v1/a/login`
- `GET /api/v1/get-my-info`
- `GET /api/v1/logout?token=...`
- `GET /api/v1/mobile/face-registration`
- `POST /api/v1/mobile/face-registration`

### zkteco app (public mobile API)

- `GET /api/v1/mobile/attendance-requests?employee_id=...`
- `POST /api/v1/mobile/attendance-requests` with `employee_id` in body

The app stores JWT locally for ERP routes only. Attendance calls use the canonical `employees.id` from `get-my-info` (`user.employeeId`).

## Canonical device and employee mapping

- display employee code comes from `employee_id` / `emp_id` in profile
- attendance submissions use `canonicalEmployeeId` (`employees.id`) for zkteco PIN alignment
- mobile submissions include a persistent `deviceIdentifier` stored in `SharedPreferences`
- zkteco registers that device in `new_attendance_devices`

## Build commands

### Run on Android Emulator (Cursor)

See [docs/EMULATOR_TESTING.md](docs/EMULATOR_TESTING.md).

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\start-android-emulator.ps1
C:\flutter\bin\flutter.bat run -d emulator-5554
```

In Cursor: **Tasks: Run Task** → **Start Android Emulator**, then **Run and Debug** → **Attandance_App (emulator)**.

### Production APK (live backends — default for distribution)

Lightweight **split-per-ABI** APKs against **production** URLs (`hrm.peoplesitsolution.com` + `zkteco.peoplesitsolution.online`). **Do not** pass `USE_LOCAL_TUNNEL_BACKENDS`.

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1
# Optional marketing bump: -UpdateLevel Minor|Medium|Major
# Emulator x86_64: add -Emulator
```

Each run bumps `pubspec.yaml` build number (`+N`). Profile → About shows `v{version}+{buildNumber}`.

Outputs (phone):

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — modern phones
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` — 32-bit phones

Emulator (x86_64 AVD):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Emulator
```

Equivalent manual phone build:

```powershell
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols
```

Install the ABI that matches the device (prefer `app-arm64-v8a-release.apk`). Do **not** ship a fat multi-ABI APK for phones.

### Dev APK (tunnel backends — local PC / Cloudflare only)

Use this only when testing against Docker stacks on this PC via Cloudflare tunnel. **Not** for production distribution.

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
# Optional marketing bump: -UpdateLevel Minor|Medium|Major
#   Minor  2.2.1 -> 2.2.2 | Medium 2.2.1 -> 2.3.1 | Major 2.2.1 -> 3.2.1
# Default -UpdateLevel Build keeps X.Y.Z and only increments +N
```

Each run bumps `pubspec.yaml` build number (`+N`). Profile → About shows `v{version}+{buildNumber}`.

Outputs (phone):

- `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` — modern phones
- `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` — 32-bit phones

Emulator (x86_64 AVD):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -Emulator
```

Equivalent manual phone build:

```powershell
flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true
```

Install the ABI that matches the device (prefer `app-arm64-v8a-release.apk`). Do **not** ship a fat multi-ABI APK for phones.
## Configuration (`lib/config/app_config.dart`)

| Define | Purpose |
|--------|---------|
| `USE_LOCAL_TUNNEL_BACKENDS` | `true` → tunnel hostnames above |
| `AUTH_API_BASE_URL` | Override HRM/ERP base |
| `ATTENDANCE_API_BASE_URL` | Override ZKTeco base |
| `API_BASE_URL` | Legacy alias for auth/ERP base |
| `API_BASE_URLS` | Auth fallback list (comma-separated) |
| `ATTENDANCE_API_BASE_URLS` | Attendance fallback list |
| `USE_SALES_DEMO_DATA` | `false` (default) → live person-sales report; `true` → demo reporting |
| `SALES_API_BASE_URL` | Sales host (default `https://sales.peoplesitsolution.online`) |
| `USE_PAYMENT_DEMO_DATA` | `true` (default) → Payments demo UI; `false` → live HRM payment APIs |

`backendApiBaseUrl` is an alias for the HRM/ERP base (leaves, holidays, sales, payments, etc.).

## Run backends locally (Docker)

**ERP** — from workspace root:

```powershell
powershell -ExecutionPolicy Bypass -File .\start_pphl_erp_and_frontend.ps1
```

**ZKTeco** — sync and redeploy:

```powershell
cd .\zkteco_deployment\scripts
powershell -ExecutionPolicy Bypass -File .\sync-full-backend.ps1
cd ..\docker
powershell -ExecutionPolicy Bypass -File .\scripts\up.ps1 -Build
powershell -ExecutionPolicy Bypass -File .\scripts\migrate.ps1
```

Ensure Cloudflared services `Cloudflared-hrmlocal` and `Cloudflared-zktecolocal` are running before testing the dev APK on a phone.
