# Mobile Employee Features (v2.2.0)

Last updated: August 19, 2026

This document describes the employee self-service modules in **Attandance_App**. HRM/ZKTeco APIs are wired where available. **Sales Info reporting and Post Sale create are live** when demo flags are off. **Auth-wise payment report and receive** use the sales host when `payment.enabled` is on. HRM loan/payslip screens still demo by default (see [SALES_AND_PAYMENTS_API_CONTRACT.md](SALES_AND_PAYMENTS_API_CONTRACT.md)).

---

## Navigation

On **every cold start and when returning from background**, the app checks notifications, camera, and location (foreground + background). If any are missing, a blocking **Permissions** screen appears before login or the main shell. Users cannot proceed until all are granted.

| Entry point | Destination |
|-------------|-------------|
| Footer **Services** tab | `EmployeeServicesHubScreen` (Attendance Report, Leave, Payments, HR Benefits, Sales Info, Vehicles, Farm & Dealer, Geo Tracking) |
| Profile → Quick Actions → Leave Request | `LeaveHubScreen` |
| Profile → Quick Actions → View Reports | `AttendanceReportScreen` |
| Profile → Settings → Location Services | `GeoTrackingScreen` |
| Attendance tab → Full Report | `AttendanceReportScreen` |

### Services tab (footer)

- Attendance Report
- Leave (single page: balance cards + history report + apply)
- Payments (dealer auth-wise report + receive payment — live when `payment.enabled`)
- HR Benefits (payslips, loans, PF, mess, compensation, post payment — demo by default)
- Sales Info (live overall + module breakdown; Post sale with searchable dealer list)
- Vehicles (fleet list → Maintenance / Trips per vehicle; unfiltered)
- Farm & Dealer (field collection: dealers, farms, visits, surveys, follow-ups)
- Geo Tracking (Google Maps; status only — no on/off toggle; auto-enabled after first-launch permissions)

---

## First-launch permissions (blocking)

Required before login / main shell (`AppPermissionsService.requiredItems`):

1. Notifications  
2. Camera  
3. Location (while using app)  
4. Location (all the time) — background geo tracking  

Geo tracking turns on automatically once these are granted (`GeoTrackingService.ensureEnabledIfAllowed`). The Geo Tracking screen shows **Tracking on/off** status and permission subtitle only — no user toggle. Logout still pauses schedules via `pauseForLogout`.

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
| Vehicle trips | Transport `GET /api/get-trips-list` (no auth; `vehicle_id` query + client filter) | **Live** |
| Farm & Dealer (marketing) | ZKTeco `/api/v1/mobile/marketing/*` (no JWT; `employee_id` = `canonicalEmployeeId`) | **Wired** (requires `marketing.enabled=true`) |
| Post sale / booking | Sales `POST /api/sales-person-sales` (egg, fertilizer, liveBird, cullBird) or `POST /api/booking-person-books` (feed, chicks) | **Live** when `USE_SALES_DEMO_DATA=false`; dealers from `GET /api/all-dealer-lists`; booking masters from `GET /api/booking-person-books/form-data` |
| Auth-wise payment post | Sales `POST /api/auth-wise-payments` (form-data, `payments[]` ADD/SAVE queue) | **Live** when `payment.enabled=true`; setup from `GET /api/payment-setup-data`; dealers from `GET /api/all-dealer-lists` |
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
- **Post sale / booking** FAB opens a sheet:
  - **Post booking** (`PostBookingScreen`) — Feed vs Chicks layouts matching sales web create pages: booking point, feed category cascade, Sale/Sample, dealer (feed list), booking-money + advance, multi-line products, Discount / Flat Discount, chicks **Zone** dropdown from `GET /api/all-dealer-lists` `data.zoneList` (POSTs `cZoneId`) + multi-delivery. POST `booking-person-books` with `Sale`/`Sample` and `Discount`/`Flat Discount`.
  - **Post sale** (`PostSaleScreen`) — egg / fertilizer / live bird / cull bird order form (`sales-person-sales`).
- Receive payment (`PostAuthWisePaymentScreen`) matches the sales web create page: Payment For, rec type, cascading dealer/employee receiver, invoice type, payment mode extras, ADD queue, SAVE. POST maps `paymentMode` 1–8, `paymentType` = bank id, `paymentFor` = type list, dealer vs `employeeId` receivers.
- Force reporting demo: `--dart-define=USE_SALES_DEMO_DATA=true`
- Override sales host: `--dart-define=SALES_API_BASE_URL=...`

### Vehicles (live)

- Services tile **Vehicles** → full active fleet (`GET /api/get-vehicle-active-list`); header **Vehicles** / “Active fleet”
- Tap a vehicle → hub with **Maintenance** and **Trips** (no employee filter)
- Maintenance: `GET /api/get-vehicle-m-history/{id}` (jobs, parts, costs)
- Trips: `GET /api/get-trips-list` paginated, filtered to this vehicle (`vehicle_id` query + client-side). Chips: All, In transit, Delivered, Draft, Cancelled, Archived. Tap a trip → detail from the same object
- Host: `https://transport.peoplesitsolution.online` (override `--dart-define=TRANSPORT_API_BASE_URL=...`)
- Requires ZKTeco `vehicle.enabled=true`. See [VEHICLES_API.md](VEHICLES_API.md)

### Farm & Dealer (marketing)

- Services tile → hub (Markets, Dealers, Farms, Visits, Follow-ups) + New Market / New Dealer / New Farm FABs
- Party create: `employee_id` required; **Company/Sector dropdowns** from Sales `GET /api/booking-person-books/form-data`; farms can link parent dealer; products, photos
- Create forms **auto-fill GPS + address** (no Capture GPS / Check-in GPS buttons); visits start `in_progress` with auto check-in; check-out completes visit; farm survey + follow-ups from party detail
- ZKTeco `/api/v1/mobile/marketing/*` including `visits/{id}/check-in|check-out` (no JWT); flag `marketing.enabled`
- See [FARM_DEALER_MOBILE.md](FARM_DEALER_MOBILE.md) for endpoint keys and payloads

### Post booking Zone dropdown (v2.2.3+44)

- Chicks **Zone** is a searchable dropdown from `GET /api/all-dealer-lists` `data.zoneList` (`id`, `zoneName`); selected `id` is posted as `cZoneId`
- No numeric Zone ID field. Product pick and submit stay blocked until a zone is selected (`Please select Zone first!`)
- Empty `zoneList` (server not deployed yet) shows a one-line helper; chicks booking cannot be posted until the list is live

### Receive payment & Post booking UX (v2.2.3+43)

- Receive payment follows the sales web create page (not the Quick Setting modal): labeled Payment For / rec type / receiver / invoice type / payment mode extras, ADD then SAVE
- POST fields aligned with web/DB: `paymentMode` 1–8, `paymentType` = bank id, `paymentFor` = type list; dealer vs employee `receiverId`
- Post booking is a separate screen (Feed vs Chicks); Post sale is egg/fertilizer/liveBird/cullBird only

### Vehicles fleet hub (v2.2.3+48)

- Services → **Vehicles** is the full active fleet again. Tap a vehicle → **Maintenance** or **Trips** (unfiltered by logged-in user)
- Trips for that vehicle still come from `GET /api/get-trips-list` (client-filter by vehicle id)

### Vehicles trip list (v2.2.3+47)

- Services → **Vehicles** was briefly a trip list from Transport `GET /api/get-trips-list` (driver/helper = me). Replaced in **+48** by the fleet hub.

### Home Hours same-day duration (v2.2.3+46)

- Home **Hours** and weekly bars use `workedHoursOnDay`: if in/out timestamps fall on different calendar days, wall-clock times are rebased onto that day (10:43–14:21 → **3.6h**, not 27.6h)
- `mergeRecords` / `resolveTodayRecord` prefer in/out punches on the target calendar day over adjacent-day leftovers
- Pending **Update Check Out** with a checkout time already shown is unchanged (requested days can still update out)

### Face rounded frame (v2.2.3+54)

- Guide is a **rounded square** with L-corners on the same rect (no oval). Fill is judged against that frame
- Auto-capture still requires mapped height ≥ 70% of the guide and center inside a 12% inset

### Face guide single frame (v2.2.3+55)

- Registration and check-in show **one** centered rounded frame (dim cutout, border, L-corners, and capture progress share the same RRect)
- The previous faint outer progress track is gone; L-corners sit on the rounded path so they do not clip the camera card

### Face oval fill (v2.2.3+53)

- Auto-capture waits until the live face **fills the oval** (mapped height ≥ 70% of the guide, center inside a 12% inset). Front-camera preview is X-mirrored to match the box.
- Image-area floor is **16%** (preferred **20%**); live centering **±20%**
- Still registration always requires centering (slightly looser for left/right/up/down)
- Shared helper: `lib/utils/face_guide_placement.dart`

### Face capture robustness (v2.2.3+52)

- Live and still captures share an **8%** minimum face-area ratio; faces under **10%** are not acceptable; live faces over **55%** are too close
- Missing camera frame size **fails closed** (no auto-capture)
- Check-in smile/blink require a **straight** pose before JPEG verify
- Shared `FaceCaptureStage`: full camera preview with one centered dimmed rounded frame (check-in no longer clips the preview to a face path)
- Missing or corrupt 192-dim templates prompt re-registration on Home, Check-in, and Profile (login is not blocked)

### Face capture timing (v2.2.3+45)

- Registration and check-in ignore auto-capture for **2 seconds** after the camera opens so the user can aim (`Position your face in the guide`)
- Target angles must be held for **5 frames (~1 s)**; smile needs **3 consecutive** smiling frames
- Missing ML Kit Euler angles are not treated as looking straight
- 0.6 s settle after each registration capture / check-in challenge before the next auto-capture can fire

### Face check-in & registration (v2.2.3+33)

- **Attendance sync fix (v2.2.3+33):** API in-only rows no longer inherit stale local checkout times; pending days with both in/out show **Update Check Out**; POST punch synthesizes a local record when the server omits `request`; checkout refresh retries up to 5× with backoff
- **Home day-complete UI (v2.2.3+31):** approved days hide punch buttons; pending days allow checkout update
- **Pull-to-refresh:** Home screen refreshes profile + attendance on swipe down
- **Home today merge (v2.2.3+29):** machine + Android punches for the same civil day collapse via `matchesCalendarDay` (any of `attDate` / in / out timestamps) and `mergeRecords` (earliest in, latest out)
- **Punch-priority calendar day:** `effectiveCalendarDay` prefers punch timestamps over `attDate` so mismatched `request_date` rows still group correctly
- **Dual Home fetch:** today-scoped list (`from`/`to` = today) merged with recent history for weekly chart
- **Optimistic preservation:** local punch in-time kept when post-punch API refresh returns incomplete rows (retry up to 3×)
- **Home times refresh:** list parser accepts ZKTeco `records` and HRM JWT `data` arrays; all list URLs are tried and merged (no stop on first empty 200)
- **Today resolution:** `effectiveCalendarDay` uses `attDate` or punch timestamps when date is missing; Home picks the best today row (prefer rows with times, highest id)
- **Optimistic punch UI:** successful POST returns `request` → Home applies immediately, then retries list refresh (3×, 400ms apart)
- Punch POST sends explicit local `attDate` (`yyyy-MM-dd`); `pending` status normalized to `requested` for subtitles
- **Approved vs pending:** Home subtitle shows *Approved* or *Pending approval* based on today's record status
- **Single check-in route:** Home guards against double-tap; only one `CheckInScreen` may be active (static route guard + opening lock)
- Successful punch auto-returns to Home after ~1.5s (or **Done**) with the punched record; Home refreshes from API after optimistic merge
- Live camera uses **image stream** (~5 FPS) with **NV21** on Android and **device-orientation-aware** ML Kit rotation
- Registration live path matches check-in: **placement + angle hold only**; strict quality runs on final `takePicture()` capture
- Live framing must **fill the centered rounded frame** (≥ 70% of guide height, plus ≥ 16% of the camera image); a distant face cannot look “in frame” because the preview is no longer clipped
- Early check-in verify uses single embedding pass; final match keeps robust 4-variant embedding

### Geo map (v2.2.3+51)

- Geo Tracking uses **native Google Maps** (`google_maps_flutter`)
- Layer switcher: **Standard** = `MapType.normal`, **Detailed** = `MapType.terrain`, **Satellite** = `MapType.hybrid` (imagery plus labels)
- Live marker, GPS accuracy circle, and recent-ping pins are unchanged
- Default zoom remains **17** live / **15** history
- Zoom **+ / −** controls and recenter are still available beside the map
- Requires Maps SDK for Android enabled on the Google Cloud key restricted to `com.pphl.employee_attendance`

### Payments hub (v2.3)

- **Dealer payments only:** live auth-wise payment-receive report (same host as Sales) — date chips, overall KPIs, module tabs (Egg…Other)
- **Receive dealer payment:** searchable bank, receiver, and payment type from `payment-setup-data`; rec type / payment for / invoice type remain numeric fields
- When `payment.enabled` is off: banner explains dealer report is disabled; open **Services → HR Benefits** for payslips and loans
- Dealer report errors: app shows sales JSON **`error`** field as headline (e.g. Bengali account-link text), English **action hint** as subtitle, amber banner for setup/422 (not generic red title)
- Eligibility: must be listed in `payment-setup-data` `employeeList` before report loads
- Feature flag alias: `feature.payment.enabled` ↔ `payment.enabled`
- Requires ZKTeco `payment.enabled=true` and endpoint `payment.authWise` for live dealer report/receive

### HR Benefits hub

- Dedicated Services tile: payslips, loans, loan payments, post payment, PF, mess deposit, compensation
- Demo payroll/loan data by default (`USE_PAYMENT_DEMO_DATA`); independent of dealer `payment.enabled`

### Forced OTA updates (v2.2.3+)

Full reference: [OTA_UPDATES.md](OTA_UPDATES.md)

- On cold start, `UpdateGate` checks `UPDATE_MANIFEST_URL` (GitHub raw `ota/manifest.json` on [ciphercall/rocket-launcher](https://github.com/ciphercall/rocket-launcher))
- APKs download from GitHub Release asset URLs in the manifest (public, no auth)
- When remote `version_code` > installed build: blocking **Update required** screen (`force_update: true` — no skip except offline on fetch errors)
- Download shows progress bar with size and percentage; interrupted downloads restart on next launch (no resume)
- After download: SHA-256 verified → system install dialog → relaunch via `MY_PACKAGE_REPLACED`
- **Publish:** double-click `Attandance_App/PUBLISH-OTA-UPDATE.cmd` (or `rocket launcher/PUBLISH-OTA-UPDATE.cmd`), enter release notes, wait ~3–5 min
- **First install** on each device: manual APK once (OTA-enabled baseline); all later releases are OTA-only
- Disable checks in dev: `--dart-define=UPDATE_CHECK_ENABLED=false`
- **Verified** on real device: v40 → v41 OTA, August 2026

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
flutter build apk --release --dart-define=USE_LOCAL_TUNNEL_BACKENDS=true --dart-define=USE_PAYMENT_DEMO_DATA=false --split-per-abi --target-platform android-arm,android-arm64 --no-tree-shake-icons --obfuscate --split-debug-info=build/app/outputs/symbols
```

Force sales reporting demo:

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --no-tree-shake-icons --obfuscate --split-debug-info=build/app/outputs/symbols --dart-define=USE_SALES_DEMO_DATA=true
```

Version: **2.2.x** (marketing + build bumped via tunnel script `-UpdateLevel`)
