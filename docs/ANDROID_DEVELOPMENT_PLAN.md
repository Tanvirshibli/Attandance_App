# Android Implementation Plan (Cursor)

Implementation reference for the PPHL Attendance App dual-backend integration. See [CLIENT_ANDROID_APP_DEVELOPMENT_PLAN.md](CLIENT_ANDROID_APP_DEVELOPMENT_PLAN.md) for stakeholder documentation.

## Completed implementation

### ZKTeco (`zkteco-Automation-management-PPHL`)

- `mobile_app_endpoint_configs` table + seeder
- `GET /api/v1/mobile/app-config` (public)
- Settings → Mobile App API (Livewire)
- `mobile_location_pings` + `POST/GET /api/v1/mobile/geo-location`
- `mobile_fcm_tokens` + `POST /api/v1/mobile/fcm-token`
- `face_verified` on attendance requests
- Tests: `MobileAppConfigApiTest`, `MobileGeoLocationApiTest`

### HRM (`pphl_erp`)

- `GET /api/v1/mobile/holidays` (department-scoped)
- `EnforcesMobileEmployeeScope` on leaves + new-leave-stocks
- `POST /api/v1/refresh` implemented

### Android (`Attandance_App`)

- `EndpointConfigService` + `ServerBootstrapScreen`
- All services use dynamic URLs with `AppConfig` fallback
- Geo: 5-min interval, ZKTeco upload, WorkManager background
- Payment/Sales gated by feature flags (dummy default)
- Attendance report: punch timeline, face badge, geo address
- Leave hub: upcoming holidays

## Key files

| Area | Path |
|------|------|
| Config service | `lib/services/endpoint_config_service.dart` |
| Bootstrap UI | `lib/screens/server_bootstrap_screen.dart` |
| Geo background | `lib/services/geo_background_worker.dart` |
| ZKTeco admin | `app/Livewire/Settings/MobileAppEndpointSettingsPage.php` |
| ZKTeco config API | `app/Http/Controllers/Api/Mobile/MobileAppConfigController.php` |

## Verification commands

```powershell
# ZKTeco tests
docker compose -p zkteco-production exec api php artisan test --filter=MobileApp

# HRM migrate
cd hrm_deployment\docker
powershell -ExecutionPolicy Bypass -File .\scripts\migrate.ps1

# Flutter
cd Attandance_App
flutter pub get
flutter analyze
```

## Local URLs

- HRM: `http://127.0.0.1:8020` (`hrm-production`)
- ZKTeco: `http://127.0.0.1:8095` (`zkteco-production`)
- Physical device: use PC LAN IP
