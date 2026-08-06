# Mobile Employee Features (v2.2.0)

Last updated: July 28, 2026

This document describes the employee self-service modules in **Attandance_App**. HRM/ZKTeco APIs are wired where available. **Sales Info reporting and Post Sale create are live** when demo flags are off. **Auth-wise payment report and receive** use the sales host when `payment.enabled` is on. HRM loan/payslip screens still demo by default (see [SALES_AND_PAYMENTS_API_CONTRACT.md](SALES_AND_PAYMENTS_API_CONTRACT.md)).

---

## Navigation

On **every cold start and when returning from background**, the app checks notifications, camera, and location (foreground + background). If any are missing, a blocking **Permissions** screen appears before login or the main shell. Users cannot proceed until all are granted.

| Entry point | Destination |
|-------------|-------------|
| Footer **Services** tab | `EmployeeServicesHubScreen` (Attendance Report, Leave, Payments, Sales Info, Vehicles, Farm & Dealer, Geo Tracking) |
| Profile → Quick Actions → Leave Request | `LeaveHubScreen` |
| Profile → Quick Actions → View Reports | `AttendanceReportScreen` |
| Profile → Settings → Location Services | `GeoTrackingScreen` |
| Attendance tab → Full Report | `AttendanceReportScreen` |

### Services tab (footer)

- Attendance Report
- Leave (single page: balance cards + history report + apply)
- Payments (payslips, loans, PF, mess, compensation, post payment — demo by default)
- Sales Info (live overall + module breakdown; Post sale with searchable dealer list)
- Vehicles (active fleet list + maintenance history)
- Farm & Dealer (field collection: dealers, farms, visits, surveys, follow-ups)
- Geo Tracking

---

## API mapping

| Feature | Endpoint | Status |
|---------|----------|--------|
| Attendance report (list) | ZKTeco `GET /api/v1/mobile/attendance-requests?employee_id=` (primary) + HRM JWT merge | **Wired** |
| Attendance summary | HRM `GET /api/v1/single-employee-attendance-details` | **Wired** (Home KPIs count `data.rows[].attendanceType`) |
| Home today status | Merged ZKTeco + HRM list (one row per day) | **Wired** |
| Leave balance | HRM `GET /api/v1/new-leave-stocks?employeeId=` (+ enrich via `leavetypes` **id→lName** / code when `leaveName` empty; stocks often store legacy type ids) | **Wired** |
| Leave history | HRM `GET /api/v1/leaves?employeeId=` | **Wired** |
| Apply leave | HRM `GET /api/v1/leavetypes`, `POST /api/v1/leaves` | **Wired** |
| Payslips | HRM `GET /api/v1/payroll?employeeId=` · `GET /api/v1/payroll/{id}` | **Demo default** / live when `USE_PAYMENT_DEMO_DATA=false` |
| Loans | HRM `GET /api/v1/loans-employee` · `GET /api/v1/loan/{id}` | **Demo default** / live ready |
| Post payment (loan) | HRM `POST /api/v1/pay-loan/store` | **Demo default** / live ready |
| Payment report | HRM `GET /api/v1/get/pay-loan?employeeId=` | **Demo default** / live ready |
| Provident fund | HRM `GET /api/v1/providentfunds-employee` · `/providentfunds` | **Demo default** / live ready |
| Mess deposit | HRM `GET /api/v1/mess-deposit-employee` | **Demo default** / live ready |
| Compensation | HRM `GET /api/v1/facility-employee` | **Demo default** / live ready |
| Sales eligibility | HRM `GET /api/get-sales-employee-list` | **Wired** |
| Sales person report | Sales `GET /api/sales-person-sales/{employeeId}?from_date=&to_date=` (no auth) | **Live** (default host `https://sales.peoplesitsolution.online`; requires ZKTeco `sales.enabled=true`) |
| Auth-wise payments | Sales host `GET /api/auth-wise-payments/{employeeId}?from_date=&to_date=` (no auth) | **Live** (requires ZKTeco `payment.enabled=true`) |
| Vehicles list | Transport `GET /api/get-vehicle-active-list` (no auth) | **Live** (requires ZKTeco `vehicle.enabled=true`) |
| Vehicle maintenance | Transport `GET /api/get-vehicle-m-history/{id}` (no auth) | **Live** |
| Farm & Dealer (marketing) | ZKTeco `/api/v1/mobile/marketing/*` (no JWT; `employee_id` = `canonicalEmployeeId`) | **Wired** (requires `marketing.enabled=true`) |
| Post sale / booking | Sales `POST /api/sales-person-sales` (egg, fertilizer, liveBird, cullBird) or `POST /api/booking-person-books` (feed, chicks) | **Live** when `USE_SALES_DEMO_DATA=false`; dealers from `GET /api/all-dealer-lists` |
| Auth-wise payment post | Sales `POST /api/auth-wise-payments` (form-data) | **Live** when `payment.enabled=true`; setup from `GET /api/payment-setup-data` |
| Payment setup lists | Sales `GET /api/payment-setup-data` | **Live** (banks, receivers, payment types) |
| All dealer lists | Sales `GET /api/all-dealer-lists` | **Live** (module-filtered searchable dropdown on Post sale) |
| Geo location upload | ZKTeco `POST /api/v1/mobile/geo-location` | **Wired** |
| App endpoint config | ZKTeco `GET /api/v1/mobile/app-config` | **Wired** |
| Holidays | HRM `GET /api/v1/mobile/holidays` | **Wired** |
| JWT refresh | HRM `POST /api/v1/refresh` | **Wired** |
| Geo history | ZKTeco `GET /api/v1/mobile/geo-location` | **Wired** |
| FCM token register | ZKTeco `POST /api/v1/mobile/fcm-token` | **Wired** (`google-services.json` present for Android) |
| FCM wake for geo | Firebase Cloud Messaging + ZKTeco `zkteco:geo-fcm-wake` | **Wired** (local stack: `GEO_FCM_WAKE_ENABLED` + service account in container storage) |

Handoff for backend teams: **[SALES_AND_PAYMENTS_API_CONTRACT.md](SALES_AND_PAYMENTS_API_CONTRACT.md)**.

### Sales Info (live reporting)

- Header uses API `employee.employeeName` (fallback profile name)
- Date presets: This month / Last month / Custom → `from_date` / `to_date`
- Overall KPIs: orders, returns, net/gross sales, net qty
- Module tabs: Egg | Feed | Fertilizer | Chicks | Live Bird | Cull Bird
- Per module: summary, Products / Dealers / Sectors, line details
- **Post sale / booking** FAB → feed/chicks use booking form (`booking-person-books`); other modules use sale order form (`sales-person-sales`); dealer lists loaded once per session; type-to-search dealer by name/code/phone; module switches list (Chicks/Cull Bird use live bird list for now)
- Force reporting demo: `--dart-define=USE_SALES_DEMO_DATA=true`
- Override sales host: `--dart-define=SALES_API_BASE_URL=...`

### Vehicles (live)

- Services tile → active vehicle list (`numberPlate` / `tVehicleNo`, purchase date)
- Tap vehicle → maintenance history (job title, status, costs, workshop, expandable parts)
- Host: `https://transport.peoplesitsolution.online` (override `--dart-define=TRANSPORT_API_BASE_URL=...`)
- Requires ZKTeco `vehicle.enabled=true`

### Farm & Dealer (marketing)

- Services tile → hub (Dealers, Farms, My visits, Follow-ups) + New Dealer / New Farm FABs
- Create party with GPS, product rows, multi-photo upload; visit / farm survey / follow-up from party detail
- ZKTeco `/api/v1/mobile/marketing/*` (no JWT); flag `marketing.enabled`
- See [FARM_DEALER_MOBILE.md](FARM_DEALER_MOBILE.md) for endpoint keys and payloads

### Payments hub (v2.3)

- **Primary:** live auth-wise payment-receive report (same host as Sales) — date chips, overall KPIs, module tabs (Egg…Other)
- **Receive dealer payment:** searchable bank, receiver, and payment type from `payment-setup-data`; rec type / payment for / invoice type remain numeric fields
- **Secondary HR benefits:** Payslips, My loans, Loan payments, Post payment, Provident fund, Mess deposit, Compensation (still demo by default via `USE_PAYMENT_DEMO_DATA`)
- Requires ZKTeco `payment.enabled=true` and endpoint `payment.authWise`

### Endpoint configuration

- First launch: **Server Bootstrap** — enter ZKTeco base URL only
- Admin maps APIs in ZKTeco: **Settings → Mobile App API**
- Feature flags: `sales.enabled`, `payment.enabled`, `vehicle.enabled`, `geo.tracking.enabled`, `marketing.enabled`
- Sales reporting defaults live; Payments remain demo until dart-define flip

---

## Build

```powershell
# Build number only (+N); keep marketing version
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1

# Minor marketing bump: 2.2.1 -> 2.2.2 (+N also increments)
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -UpdateLevel Minor

# Medium: 2.2.1 -> 2.3.1
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -UpdateLevel Medium

# Major: 2.2.1 -> 3.2.1
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -UpdateLevel Major

# Emulator x86_64
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1 -Emulator -UpdateLevel Build
```

`build-dev-tunnel-apk.ps1` always increments the Flutter build number (`+N`). Optional `-UpdateLevel`:

| Level | Marketing change | Example |
|-------|------------------|---------|
| `Build` (default) | unchanged | `2.2.1+8` → `2.2.1+9` |
| `Minor` | bump patch `Z` | `2.2.1` → `2.2.2` |
| `Medium` | bump middle `Y` (keep `Z`) | `2.2.1` → `2.3.1` |
| `Major` | bump major `X` (keep `Y.Z`) | `2.2.1` → `3.2.1` |

Profile → About shows live `v{version}+{buildNumber}` via `package_info_plus` (logical `+N`; split-per-ABI APKs encode Android `versionCode` as `abi*1000+N`).

Live payments:

```powershell
flutter build apk --release --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true --dart-define=USE_PAYMENT_DEMO_DATA=false --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols
```

Force sales reporting demo:

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define=USE_SALES_DEMO_DATA=true
```

Version: **2.2.x** (marketing + build bumped via tunnel script `-UpdateLevel`)
