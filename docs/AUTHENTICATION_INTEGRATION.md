# Authentication & Mobile Attendance Integration

Last updated: August 11, 2026

## Summary

The app uses a **dual-backend** integration aligned with PeoplesHRM:

- **pphl_erp** — JWT auth, profile, face registration, and future ERP features (leave, holiday, sales, payment)
- **zkteco-Automation-management-PPHL** — public mobile attendance requests (no JWT); **primary** source for Home/History punches (same DB as the web Attendance Requests grid)

### Attendance list merge (August 11, 2026)

1. Fetch ZKTeco `GET /api/v1/mobile/attendance-requests?employee_id=` (machine + android rows).
2. Fetch HRM JWT `GET /api/v1/mobile/attendance-requests` when a token exists.
3. Merge by calendar day (earliest in / latest out). Do **not** stop after a non-empty JWT list — that previously hid ZKTeco machine punches.
4. **List response shapes:** ZKTeco returns `records[]`; HRM JWT returns `data[]` — both are parsed and merged.
5. **List URL fallback:** every configured list URL is tried; empty `records`/`data` does not short-circuit remaining URLs.
6. **Punch optimistic merge:** `POST` 201 body includes `request` (attDate, requestedInTime/Out, status). The app applies this on Home immediately, then retries GET (3×, 400ms) for server sync.
7. **Calendar day:** rows match "today" via `matchesCalendarDay` (any of `attDate`, in/out timestamps); grouping prefers punch timestamps over `attDate`; POST includes explicit local `attDate`.
8. **Home today merge (v2.2.3+29):** `resolveTodayRecord` merges all same-day rows (machine in + android out); dual fetch (today-scoped + history); local punch preserved when API list lags.
9. **Home day-complete UI (v2.2.3+31):** approved days hide punch buttons; pending days allow **Update Check Out**.
10. **Attendance sync (v2.2.3+33):** `preserveLocal` trusts API in-only over stale local out; `synthesizePunchRecord` on POST; list span-merge + unique `(employee_id, request_date)` on ZKTeco backend.
11. **ZKTeco list merge (v2.2.3+33):** mobile list API merges duplicate same-day rows (earliest in, latest out).

### Punch write path and the server-side mirror (November 2026)

- A punch POST goes to the **first base that answers**, and the order comes from the payload: a punch carrying
  biometric proof (face/fingerprint) tries **HRM** first and falls through to ZKTeco only on a 404; a punch
  without proof goes to the ZKTeco attendance base.
- The two backends now **mirror the day between themselves** (`POST /api/v1/integration/mobile-attendance-day`,
  span merge: earliest in / latest out, idempotent), so a punch stored in one appears in the other without the
  app resending anything. The merged list above is unchanged.
- Both backends run `Asia/Dhaka` and the app sends local wall-clock timestamps without an offset — that is the
  supported contract. A future build may send UTC (`Z`); nothing breaks if it does.
- The server is the source of truth for the punch instant: HRM clamps a future `self_punch` to server time and
  answers `effective.timeAdjusted` (ignored by current builds), and ZKTeco does the same for its own writes, so
  an "Update Check Out" may land a few minutes earlier than the phone showed.

## Backend endpoints

### pphl_erp (JWT required)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/v1/a/login` | Login |
| GET | `/api/v1/get-my-info` | Profile + `face_registration` |
| POST | `/api/v1/refresh` | JWT refresh |
| GET | `/api/v1/logout?token=...` | Logout |
| GET | `/api/v1/mobile/face-registration` | Optional face fetch |
| POST | `/api/v1/mobile/face-registration` | Face upsert + `zktecoPin` |

### pphl_erp biometric endpoints (build 9038)

Same HRM base as face registration. Fingerprint credentials are Keystore
public keys, never templates — see [BIOMETRIC_AUTH.md](BIOMETRIC_AUTH.md).

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| POST | `/api/v1/mobile/biometric-challenge` | none/bearer | Nonce for `purpose: "login" \| "punch"` |
| POST | `/api/v1/mobile/biometric-login` | none | `{credentialId, nonce, signature}` → `{token, user}` |
| POST | `/api/v1/mobile/biometric-punch-authorization` | JWT | Fingerprint grant quoted by the punch |
| GET | `/api/v1/mobile/biometric-credentials` | JWT | Credentials + `preferences` |
| POST | `/api/v1/mobile/biometric-credentials` | JWT | Register `publicKey`, `keyAlias`, `algorithm: "ES256"` |
| DELETE | `/api/v1/mobile/biometric-credentials/{credentialId}` | JWT | Revoke |
| PUT | `/api/v1/mobile/biometric-preferences` | JWT | `{login:{face,fingerprint}, checkin:{face,fingerprint}}` |

Signatures are ECDSA `SHA256withECDSA` (DER, base64) over the UTF-8 nonce;
`publicKey` is `KeyPair.public.encoded` (X.509 SPKI, base64).

### zkteco app (no JWT)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/v1/mobile/attendance-requests?employee_id=` | List employee records |
| POST | `/api/v1/mobile/attendance-requests` | Check-in/out self punch |

POST body includes `employee_id` (canonical `employees.id`), `direction`, `attDate` (local `yyyy-MM-dd`), geo fields, and device metadata. Build 9038 adds `biometric_method` (`face` | `fingerprint`) and, for fingerprint, `biometric_authorization_id` from
`POST /api/v1/mobile/biometric-punch-authorization`.

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

- `AuthService` — ERP JWT session (`applyBiometricSession` adopts a biometric
  session; `storeFaceLoginSecrets` / `clearFaceLoginSecrets` own the encrypted
  token face login refreshes from)
- `FaceRegistrationApiService` — ERP face upsert
- `BiometricApiService` / `BiometricAuthService` — ERP biometric credentials,
  challenges and punch authorisations
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
