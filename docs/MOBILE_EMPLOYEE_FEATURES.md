# Mobile Employee Features (v2.1.0)

Last updated: July 9, 2026

This document describes the employee self-service modules in **Attandance_App**. HRM/ZKTeco APIs are wired where available; Sales/Payment stay flag-gated placeholders until product backends are ready.

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
| Attendance report (list) | ZKTeco `GET /api/v1/mobile/attendance-requests?employee_id=` (primary) + HRM JWT merge | **Wired** |
| Attendance summary | HRM `GET /api/v1/single-employee-attendance-details` | **Wired** (Home KPIs count `data.rows[].attendanceType`) |
| Home today status | Merged ZKTeco + HRM list (one row per day) | **Wired** (today-only clocked-in; open shift hours use `now`; includes `deviceType=zkteco`) |
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
| JWT refresh | HRM `POST /api/v1/refresh` | **Wired** (client retry on 401) |
| Geo history | ZKTeco `GET /api/v1/mobile/geo-location` | **Wired** |
| FCM token register | ZKTeco `POST /api/v1/mobile/fcm-token` | **Scaffold** (needs `google-services.json`) |
| FCM wake for geo | Firebase Cloud Messaging | **Scaffold** (no Firebase deps until config file exists) |

All HRM calls use dynamic endpoints from `EndpointConfigService` (fetched from ZKTeco `GET /api/v1/mobile/app-config`) with JWT from login. Fallback: `AppConfig` compile-time URLs when config fetch fails. Config is refreshed after login and on app resume.

### Home dashboard data

- **Clocked in** only when **today** has an open check-in (no checkout, not rejected). Prior-day open punches do not show “You’re Clocked In.”
- Check In / Check Out / Hours and the green status card use the same today record; times parse `Y-m-d H:i:s` and related formats via `AttendanceRequestRecord.parseFlexibleDateTime`.
- **Present / Absent / Holiday / Leave** come from single-employee daily `rows` (`attendanceType`). If that payload is missing/empty but punch requests exist for the month, Present is estimated from distinct check-in days.
- **Weekly Hours** includes open shifts (checkout missing → end = now).
- Load order: profile → attendance list → summary.
- **Attendance source of truth:** ZKTeco BFF (same DB as web Attendance Requests). The app always loads ZKTeco when `employeeId` is known, merges HRM JWT rows, and collapses to **one row per calendar day** (earliest in, latest out). Machine (`zkteco`) and phone (`android`) punches both display; `deviceType` may be `mixed` after merge.
- Same-day **machine in + android out** is supported on the ZKTeco backend (`AttendanceRequestWorkflowService` updates one employee/day row).

### Endpoint configuration (v2.2)

- First launch: **Server Bootstrap** screen — enter ZKTeco base URL only
- Admin maps all APIs in ZKTeco dashboard: **Settings → Mobile App API**
- Feature flags: `sales.enabled`, `payment.enabled`, `geo.tracking.enabled` (payment/sales default off)

### Auth reliability

- `AuthService.refreshToken()` calls mapped `auth.refresh`
- `HrmApiClient` retries once after 401 when refresh succeeds; otherwise clears session

---

## Geo tracking

### What works now

- Redesigned **Geo Tracking** screen with a live OpenStreetMap window (`flutter_map`)
- Live GPS marker + accuracy circle; recenter control; history markers on the map
- Tap a recent ping to fly the map to that location
- Toggle on/off tracking with polished status chips (interval, pending, WorkManager, FCM)
- Foreground + background location permission flow
- Manual **Capture Now** and in-app periodic timer (interval from dashboard, default 5 min)
- WorkManager periodic task (~15 min OS minimum)
- Ongoing local notification while tracking is enabled
- Local queue in `SharedPreferences` when upload endpoint is unavailable
- Recent history list (ZKTeco history API, local queue fallback)

### Android permissions added

- `ACCESS_BACKGROUND_LOCATION`
- `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION`
- `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `POST_NOTIFICATIONS`

### FCM enable steps (when ready)

1. Create Firebase project; add Android app package `com.pphl.employee_attendance`.
2. Place `google-services.json` in `android/app/`.
3. Add `firebase_core` + `firebase_messaging` and Google Services Gradle plugin.
4. Wire `FcmWakeHandler.register()` to messaging listeners; call `onWakeRequested()` → `captureAndQueue(source: 'fcm_wake')`.
5. After obtaining a device token, call `registerTokenWithBackend(employeeId, token)`.

### Reliability notes

Modern Android may defer background work when the app is force-stopped or battery-restricted. Users should disable battery optimization for reliable tracking until FCM orchestration is live.

---

## New files (summary)

**Screens:** `employee_services_hub_screen`, `attendance_report_screen`, `leave_hub_screen`, `leave_balance_screen`, `leave_report_screen`, `apply_leave_screen`, `payment_hub_screen`, `post_payment_screen`, `payment_report_screen`, `sales_info_screen`, `geo_tracking_screen`

**Services:** `hrm_api_client`, `attendance_report_service`, `leave_service`, `payment_service`, `sales_service`, `geo_tracking_service`, `fcm_wake_handler`

**Widgets:** `gradient_screen_header`, `section_card`, `filter_chip_row`, `api_empty_state`, `date_range_field`, `live_location_map`

---

## Build

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
```

Version: **2.1.0+4**
