# Auth, geo HRM load, and 429 handling

## Context

The app authenticates against `https://hrm.peoplesitsolution.com` (pphl_erp). Heavy HRM traffic previously came from geo tracking calling `GET /api/v1/get-my-info` on **every** upload and once **per queued ping** during flush. Combined with Laravel’s old **60/min per IP** throttle, that produced 429s for some users (especially geo-on) while others were fine. Retrying login as the same user could still 429 while background geo kept the IP hot; logging in as another user after logout often succeeded.

## Changes

### Auth (`lib/services/auth_service.dart`)

- **Single-flight** `refreshToken()` (mutex via `Completer`) so concurrent 401s share one refresh.
- In-memory **profile cache** (~20 minutes) to avoid repeated `get-my-info`.
- Login surfaces a clear message on HTTP 429.
- Logout clears profile cache and calls `GeoTrackingService.pauseForLogout()`.
- Successful login clears geo HRM pause.

### Geo (`lib/services/geo_tracking_service.dart`)

- Resolve employee id from cache / one profile fetch; **flushQueue resolves once per batch**.
- On upload HTTP 429: pause HRM-bound geo for `Retry-After` or 60s.
- `pauseForLogout()` cancels foreground timer + WorkManager task so leftover traffic cannot block the next login.

### Face / HRM client

- Face registration attempts **refresh once** on 401 before local logout.
- `HrmApiClient` returns a non-logout failure for 429.

## Related backend

Deploy matching pphl_erp changes: per-JWT rate limits, `POST /api/v1/refresh` outside `jwt.verify`, TrustProxies. See `pphl_erp/docs/AUTH_AND_RATE_LIMITS.md`.
