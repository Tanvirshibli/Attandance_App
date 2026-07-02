# employee_attendance

Flutter Android app for PPHL attendance.

## Current integration scope

- Login/auth session: JWT on `pphl_erp`
- Face registration: JWT on `pphl_erp` → `face_registration_android`
- Check-in/check-out + attendance history: public API on `zkteco-Automation-management-PPHL` (no JWT; `employee_id` required) with HRM JWT mobile attendance preferred when logged in
- **Employee services (v2.1.0):** attendance full report, leave balance/history/apply, loan payment post/report, payroll read, sales info (placeholder metrics), geo tracking scaffold
- Home screen attendance actions: separate `Check In` and `Check Out` buttons with enable/disable rules
- Attendance records shown in app: real backend records across requested, approved, and rejected workflow states
- Dummy UI data retained for visual consistency (stats/other placeholders)
- Persistent per-install device identity sent with attendance and face-registration requests

See [docs/MOBILE_EMPLOYEE_FEATURES.md](docs/MOBILE_EMPLOYEE_FEATURES.md) for API wiring status per feature.

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

### Dev APK (tunnel backends — install on phone for testing)

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
```

Equivalent manual command:

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64 --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true
```

### Production APK

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm,android-arm64
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Configuration (`lib/config/app_config.dart`)

| Define | Purpose |
|--------|---------|
| `USE_LOCAL_TUNNEL_BACKENDS` | `true` → tunnel hostnames above |
| `AUTH_API_BASE_URL` | Override HRM/ERP base |
| `ATTENDANCE_API_BASE_URL` | Override ZKTeco base |
| `API_BASE_URL` | Legacy alias for auth/ERP base |
| `API_BASE_URLS` | Auth fallback list (comma-separated) |
| `ATTENDANCE_API_BASE_URLS` | Attendance fallback list |

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
