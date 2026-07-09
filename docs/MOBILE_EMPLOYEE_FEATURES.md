# Mobile Employee Features (v2.1.0)

Last updated: July 2, 2026

This document describes the employee self-service modules added to **Attandance_App** v2.1.0. Backend changes were **not** made in this phase — the app wires existing HRM JWT APIs where available and shows polished placeholders elsewhere.

---

## Navigation

| Entry point | Destination |
|-------------|-------------|
| Footer **Services** tab | `EmployeeServicesHubScreen` (Attendance Report, Leave, Payments, Sales Info, Geo Tracking) |
| Profile → Quick Actions → Leave Request | `LeaveHubScreen` |
| Profile → Quick Actions → View Reports | `AttendanceReportScreen` |
| Profile → Settings → Location Services | `GeoTrackingScreen` |
| Attendance tab → Full Report | `AttendanceReportScreen` |

### Services tab (footer)

- Attendance Report
- Leave (balance, history, apply)
- Payments (post loan payment, reports)
- Sales Info (role-gated placeholder metrics)
- Geo Tracking

---

## API mapping

| Feature | Endpoint | Status |
|---------|----------|--------|
| Attendance report (list) | HRM `GET /api/v1/mobile/attendance-requests` (JWT) + ZKTeco fallback | **Wired** |
| Attendance summary | HRM `GET /api/v1/single-employee-attendance-details` | **Wired** |
| Leave balance | HRM `GET /api/v1/new-leave-stocks?employeeId=` | **Wired** |
| Leave history | HRM `GET /api/v1/leaves?employeeId=` | **Wired** |
| Apply leave | HRM `GET /api/v1/leavetypes`, `POST /api/v1/leaves` | **Wired** |
| Post payment (loan) | HRM `POST /api/v1/pay-loan/store` | **Wired** |
| Payment report | HRM `GET /api/v1/get/pay-loan?employeeId=` | **Wired** |
| Payroll slips | HRM `GET /api/v1/payroll?employeeId=` | **Wired** |
| Sales eligibility | HRM `GET /api/get-sales-employee-list` | **Wired** (gate only) |
| Sales metrics | — | **Pending** (UI placeholder) |
| Geo location upload | ZKTeco `POST /api/v1/mobile/geo-location` | **Wired** (ZKTeco DB) |
| App endpoint config | ZKTeco `GET /api/v1/mobile/app-config` | **Wired** (bootstrap) |
| Holidays | HRM `GET /api/v1/mobile/holidays` | **Wired** |
| FCM wake for geo | Firebase Cloud Messaging | **Pending** (`google-services.json` not configured) |

All HRM calls use dynamic endpoints from `EndpointConfigService` (fetched from ZKTeco `GET /api/v1/mobile/app-config`) with JWT from login. Fallback: `AppConfig` compile-time URLs when config fetch fails.

### Endpoint configuration (v2.2)

- First launch: **Server Bootstrap** screen — enter ZKTeco base URL only
- Admin maps all APIs in ZKTeco dashboard: **Settings → Mobile App API**
- Feature flags: `sales.enabled`, `payment.enabled`, `geo.tracking.enabled` (payment/sales default off)

---

## Geo tracking (client scaffold)

### What works now

- Toggle on/off from **Geo Tracking** screen
- Foreground + background location permission flow
- Manual **Capture Now** and in-app periodic timer while tracking is enabled
- Local queue in `SharedPreferences` when upload endpoint is unavailable
- Last ping display (time, coordinates, address)

### Android permissions added

- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION`
- `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `POST_NOTIFICATIONS`

### Future backend + FCM steps

1. Implement `POST /api/v1/mobile/geo-location` on `pphl_erp` (accept `lat`, `lng`, `address`, `capturedAt`).
2. Add Firebase project + `google-services.json` to `android/app/`.
3. Enable `firebase_messaging` and register data messages to call `GeoTrackingService.captureAndQueue()`.
4. Add `workmanager` for true background periodic tasks when Android SDK Platform 33+ is available on the build machine.
5. Server-side scheduler can push FCM every 10 minutes for users with tracking enabled.

### Reliability notes

Modern Android may defer background work when the app is force-stopped or battery-restricted. Users should disable battery optimization for reliable tracking until FCM orchestration is live.

---

## New files (summary)

**Screens:** `employee_services_hub_screen`, `attendance_report_screen`, `leave_hub_screen`, `leave_balance_screen`, `leave_report_screen`, `apply_leave_screen`, `payment_hub_screen`, `post_payment_screen`, `payment_report_screen`, `sales_info_screen`, `geo_tracking_screen`

**Services:** `hrm_api_client`, `attendance_report_service`, `leave_service`, `payment_service`, `sales_service`, `geo_tracking_service`, `fcm_wake_handler`

**Widgets:** `gradient_screen_header`, `section_card`, `filter_chip_row`, `api_empty_state`, `date_range_field`

---

## Build

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
```

Version: **2.1.0+4**
