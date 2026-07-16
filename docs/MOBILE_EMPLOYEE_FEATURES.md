# Mobile Employee Features (v2.2.0)

Last updated: July 16, 2026

This document describes the employee self-service modules in **Attandance_App**. HRM/ZKTeco APIs are wired where available. **Sales Info** and **Payments** ship with polished demo UIs by default; flip to live APIs with dart-defines (see [SALES_AND_PAYMENTS_API_CONTRACT.md](SALES_AND_PAYMENTS_API_CONTRACT.md)).

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
- Leave (single page: balance cards + history report + apply)
- Payments (payslips, loans, PF, mess, compensation, post payment — demo by default)
- Sales Info (personal KPIs, own postings, post sale — demo by default)
- Geo Tracking

---

## API mapping

| Feature | Endpoint | Status |
|---------|----------|--------|
| Attendance report (list) | ZKTeco `GET /api/v1/mobile/attendance-requests?employee_id=` (primary) + HRM JWT merge | **Wired** |
| Attendance summary | HRM `GET /api/v1/single-employee-attendance-details` | **Wired** (Home KPIs count `data.rows[].attendanceType`) |
| Home today status | Merged ZKTeco + HRM list (one row per day) | **Wired** |
| Leave balance | HRM `GET /api/v1/new-leave-stocks?employeeId=` | **Wired** |
| Leave history | HRM `GET /api/v1/leaves?employeeId=` | **Wired** |
| Apply leave | HRM `GET /api/v1/leavetypes`, `POST /api/v1/leaves` | **Wired** |
| Payslips | HRM `GET /api/v1/payroll?employeeId=` · `GET /api/v1/payroll/{id}` | **Demo default** / live when `USE_PAYMENT_DEMO_DATA=false` |
| Loans | HRM `GET /api/v1/loans-employee` · `GET /api/v1/loan/{id}` | **Demo default** / live ready |
| Post payment (loan) | HRM `POST /api/v1/pay-loan/store` | **Demo default** / live ready |
| Payment report | HRM `GET /api/v1/get/pay-loan?employeeId=` | **Demo default** / live ready |
| Provident fund | HRM `GET /api/v1/providentfunds-employee` · `/providentfunds` | **Demo default** / live ready |
| Mess deposit | HRM `GET /api/v1/mess-deposit-employee` | **Demo default** / live ready |
| Compensation | HRM `GET /api/v1/facility-employee` | **Demo default** / live ready |
| Sales eligibility | HRM `GET /api/get-sales-employee-list` | **Wired** (gate when not demo) |
| Sales overview / list / create | External sales API (see contract doc) | **Demo default** / pending live backend |
| Geo location upload | ZKTeco `POST /api/v1/mobile/geo-location` | **Wired** |
| App endpoint config | ZKTeco `GET /api/v1/mobile/app-config` | **Wired** |
| Holidays | HRM `GET /api/v1/mobile/holidays` | **Wired** |
| JWT refresh | HRM `POST /api/v1/refresh` | **Wired** |
| Geo history | ZKTeco `GET /api/v1/mobile/geo-location` | **Wired** |
| FCM token register | ZKTeco `POST /api/v1/mobile/fcm-token` | **Scaffold** |
| FCM wake for geo | Firebase Cloud Messaging | **Scaffold** |

Handoff for backend teams: **[SALES_AND_PAYMENTS_API_CONTRACT.md](SALES_AND_PAYMENTS_API_CONTRACT.md)**.

### Sales Info (v2.2)

- Personal KPI overview (target, achieved, orders, revenue, conversion) with period chips
- **My sales** list (own postings only)
- **Post sale** form (customer, amount, date, product, quantity, notes)
- Demo banner while `USE_SALES_DEMO_DATA=true` (default)

### Payments hub (v2.2)

- Summary strip: latest net pay, open loan remaining, PF closing balance
- Sections: Payslips (list + detail), My loans, Loan payments, Post payment, Provident fund, Mess deposit, Compensation
- Demo data mirrors HRM `PayrollResource` / `LoanResource` / `LoanPaymentResource` field names
- Live switch: `USE_PAYMENT_DEMO_DATA=false` + existing JWT `/api/v1` routes (no HRM code changes)

### Endpoint configuration

- First launch: **Server Bootstrap** — enter ZKTeco base URL only
- Admin maps APIs in ZKTeco: **Settings → Mobile App API**
- Feature flags: `sales.enabled`, `payment.enabled`, `geo.tracking.enabled`
- Demo dart-defines for Sales/Payments until backends are ready

---

## Build

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build-dev-tunnel-apk.ps1
```

Live payments:

```powershell
flutter build apk --release --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true --dart-define=USE_PAYMENT_DEMO_DATA=false
```

Live sales (when external API ready):

```powershell
flutter build apk --release --dart-define=USE_SALES_DEMO_DATA=false
```

Version: **2.2.0**
