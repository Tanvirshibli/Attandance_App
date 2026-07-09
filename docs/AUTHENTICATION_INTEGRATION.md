# Authentication & Mobile Attendance Integration

Last updated: July 9, 2026

## Summary

The app uses a **dual-backend** integration aligned with PeoplesHRM:

- **pphl_erp** — JWT auth, profile, face registration, and future ERP features (leave, holiday, sales, payment)
- **zkteco-Automation-management-PPHL** — public mobile attendance requests (no JWT); **primary** source for Home/History punches (same DB as the web Attendance Requests grid)

### Attendance list merge (July 9, 2026)

1. Fetch ZKTeco `GET /api/v1/mobile/attendance-requests?employee_id=` (machine + android rows).
2. Fetch HRM JWT `GET /api/v1/mobile/attendance-requests` when a token exists.
3. Merge by calendar day (earliest in / latest out). Do **not** stop after a non-empty JWT list — that previously hid ZKTeco machine punches.

## Backend endpoints

### pphl_erp (JWT required)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/a/login` | Login |
| GET | `/api/v1/get-my-info` | Profile + `face_registration` |
| GET | `/api/v1/logout?token=...` | Logout |
| GET | `/api/v1/mobile/face-registration` | Optional face fetch |
| POST | `/api/v1/mobile/face-registration` | Face upsert + `zktecoPin` |

### zkteco app (no JWT)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/mobile/attendance-requests?employee_id=` | List employee records |
| POST | `/api/v1/mobile/attendance-requests` | Check-in/out self punch |

POST body includes `employee_id` (canonical `employees.id`), `direction`, geo fields, and device metadata.

Face embeddings are **not** sent to zkteco; they remain on pphl_erp only.

## Employee ID rules

| Field | Source | Use |
|-------|--------|-----|
| `employeeId` (display) | `user.employee_id` / `emp_id` | UI labels |
| `canonicalEmployeeId` | `user.employeeId` | zkteco attendance API |

## App configuration

See `lib/config/app_config.dart` and [TUNNEL_DEVELOPMENT.md](TUNNEL_DEVELOPMENT.md).

| Mode | HRM / ERP | ZKTeco attendance |
|------|-----------|-------------------|
| Production (default) | `https://hrm.peoplesitsolution.com` | `https://zkteco.peoplesitsolution.online` |
| Dev tunnel | `https://hrm.peoplesitsolution.online` | `https://zktecolocal.peoplesitsolution.online` |

Dev tunnel build:

```powershell
flutter build apk --release --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true
```

Or use `scripts/build-dev-tunnel-apk.ps1`.

Optional overrides:

- `AUTH_API_BASE_URL` → pphl_erp login/profile/face
- `ATTENDANCE_API_BASE_URL` → zkteco mobile attendance
- `backendApiBaseUrl` getter → same as auth base for future ERP modules

## Key services

- `AuthService` — ERP JWT session
- `FaceRegistrationApiService` — ERP face upsert
- `AttendanceRequestService` — zkteco attendance (authless, requires local login + `employee_id`)
- `DeviceIdentityService` — stable Android device identifier

## Local zkteco stack redeploy

After backend changes in `zkteco-Automation-management-PPHL`:

```powershell
cd zkteco_deployment\scripts
powershell -ExecutionPolicy Bypass -File .\sync-full-backend.ps1
cd ..\docker
powershell -ExecutionPolicy Bypass -File .\scripts\up.ps1 -Build
powershell -ExecutionPolicy Bypass -File .\scripts\migrate.ps1
```

Verify mobile API:

```powershell
curl "http://127.0.0.1:8095/api/v1/mobile/attendance-requests?employee_id=1&limit=1"
```
