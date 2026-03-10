# employee_attendance

Flutter Android app for PPHL attendance.

## Current integration scope

- Login/auth session: backend JWT (`pphl_erp`)
- Face registration: persisted to backend table `face_registration_android`
- Check-in/check-out: submitted as attendance requests to backend table `new_attendance_requests`
- Home screen attendance actions: separate `Check In` and `Check Out` buttons with enable/disable rules
- Attendance records shown in app: real backend records across requested, approved, and rejected workflow states
- Dummy UI data retained for visual consistency (stats/other placeholders)
- Persistent per-install device identity sent with attendance and face-registration requests

## Backend auth integration

This app authenticates against `pphl_erp` JWT endpoints:

- `POST /api/v1/a/login`
- `GET /api/v1/get-my-info`
- `GET /api/v1/logout?token=...`
- `GET /api/v1/mobile/face-registration`
- `POST /api/v1/mobile/face-registration`
- `GET /api/v1/mobile/attendance-requests`
- `GET /api/v1/mobile/attendance-requests?status=requested`
- `POST /api/v1/mobile/attendance-requests`

The app stores JWT token locally, loads profile + face registration from backend, keeps face data in memory for matching, and invalidates session on logout.

## Canonical device and employee mapping

- the app never chooses the canonical employee ID itself; backend identity comes from the authenticated user
- mobile submissions now include a persistent `deviceIdentifier` stored in `SharedPreferences`
- backend registers that device in `new_attendance_devices`
- any ZKTeco linkage for the same employee must use `employees.id` as the canonical PIN

## Workflow behavior

- Android check-in/check-out submits one daily attendance request row that the backend updates with in and out times
- The app now reads all latest records, not just pending ones, so checkout state remains correct after approvals
- Team leader and HR decisions are reflected through the returned workflow fields
- Submitted requests include mobile device metadata so the web app can approve and audit the real device source

## Default backend target

Production and release builds now target:

- `https://hrm.peoplesitsolution.com`

## Run backend for local network

From the workspace root, use the canonical script documented in `SERVER_COMMANDS.md`:

- `powershell -ExecutionPolicy Bypass -File .\start_pphl_erp_and_frontend.ps1`

Use your laptop LAN IP for Android physical devices only when you intentionally point the app back to a local `pphl_erp` instance for development.

## Flutter build for cloud backend

From `employee_attendance`:

- `flutter pub get`
- `flutter build apk --release`

Default primary base (when no `dart-define` is passed): `https://hrm.peoplesitsolution.com`.
Default fallback bases: none.

## Flutter build with local backend override

From `employee_attendance`:

- `flutter pub get`
- `flutter build apk --release --dart-define=API_BASE_URL=http://192.168.x.x:8080 --dart-define=API_BASE_URLS=http://10.0.2.2:8080,http://192.168.x.x:8080,http://127.0.0.1:8080`

`API_BASE_URL` is primary.
`API_BASE_URLS` is optional comma-separated fallback list.

Checkout button behavior:

- the home screen refreshes attendance state on app resume
- the app refreshes attendance state again right before opening check-in or check-out flow
- this avoids stale disabled checkout actions after network changes or background/resume cycles

Latest release build output:

- `build/app/outputs/flutter-apk/app-release.apk`
