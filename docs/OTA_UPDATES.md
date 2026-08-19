# OTA (Over-The-Air) Updates — PPHL Attendance App

Last updated: August 19, 2026

Production OTA uses **GitHub** (public repo + GitHub Releases). There is **no Cloudinary** or HRM server involved in APK hosting.

**Live deployment:** [ciphercall/rocket-launcher](https://github.com/ciphercall/rocket-launcher)  
**Manifest URL:** https://raw.githubusercontent.com/ciphercall/rocket-launcher/main/ota/manifest.json

---

## Overview

| Component | Location |
|-----------|----------|
| Publisher tooling | [`rocket launcher/`](../../rocket%20launcher/) at workspace root |
| App update gate | [`lib/widgets/update_gate.dart`](../lib/widgets/update_gate.dart) |
| Update service | [`lib/services/app_update_service.dart`](../lib/services/app_update_service.dart) |
| Update UI | [`lib/screens/app_update_screen.dart`](../lib/screens/app_update_screen.dart) |
| Manifest model | [`lib/models/app_update_manifest.dart`](../lib/models/app_update_manifest.dart) |
| Config | [`lib/config/app_config.dart`](../lib/config/app_config.dart) |

On every **cold start**, the app fetches the manifest, compares `version_code` with the installed build, and either:

- Enters the app normally (up to date)
- Shows a **blocking** update screen (newer version available)
- Shows retry/offline UI if the manifest cannot be fetched

---

## Architecture

```
┌─────────────────┐     GET manifest.json      ┌──────────────────────────┐
│  Android app    │ ─────────────────────────► │ raw.githubusercontent.com │
│  (UpdateGate)   │                            │ /ciphercall/rocket-launcher│
└────────┬────────┘                            └──────────────────────────┘
         │ version_code > installed?
         ▼ yes
┌─────────────────┐     GET APK asset          ┌──────────────────────────┐
│ AppUpdateScreen │ ─────────────────────────► │ github.com/.../releases/  │
│ download+install│                            │ download/{tag}/*.apk      │
└─────────────────┘                            └──────────────────────────┘
```

| Asset | Hosted on | URL pattern |
|-------|-----------|-------------|
| Manifest | `main` branch | `https://raw.githubusercontent.com/{owner}/{repo}/main/ota/manifest.json` |
| APKs | GitHub Release | `https://github.com/{owner}/{repo}/releases/download/{tag}/app-arm64-v8a-release.apk` |

Phones download APKs **without authentication** (public repo required).

---

## One-time setup (already done)

1. Public GitHub repo: **ciphercall/rocket-launcher**
2. [`rocket launcher/config/github.env`](../../rocket%20launcher/config/github.env) — `GITHUB_OWNER`, `GITHUB_REPO`, `GITHUB_PAT`, `UPDATE_MANIFEST_URL` (gitignored; never commit PAT)
3. Classic GitHub PAT with **`repo`** scope for publishing releases and updating manifest via API
4. **First manual install** of an OTA-enabled baseline on each device (build with `UPDATE_MANIFEST_URL` baked in). After that, updates are automatic.

See [`rocket launcher/README.md`](../../rocket%20launcher/README.md) for publisher setup details.

---

## Publishing a release (normal workflow)

**Double-click one of:**

- [`PUBLISH-OTA-UPDATE.cmd`](../PUBLISH-OTA-UPDATE.cmd) (in this project root)
- [`rocket launcher/PUBLISH-OTA-UPDATE.cmd`](../../rocket%20launcher/PUBLISH-OTA-UPDATE.cmd)

1. Enter release notes when prompted
2. Wait ~3–5 minutes (Flutter build + GitHub upload)
3. Done — users on older builds get the update on next cold start

### Other scripts

| Script | Use when |
|--------|----------|
| [`scripts/build-production-apk.cmd`](../scripts/build-production-apk.cmd) | Build split APKs only (no publish) |
| [`rocket launcher/PUBLISH-APK-ONLY.cmd`](../../rocket%20launcher/PUBLISH-APK-ONLY.cmd) | APKs already in `rocket launcher/inbox/` |

### PowerShell equivalent

```powershell
cd Attandance_App
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Publish -ReleaseNotes "Describe what changed"
```

The build script reads `UPDATE_MANIFEST_URL` from `rocket launcher/config/github.env` and passes it as `--dart-define` when compiling.

---

## App-side update flow

1. **`UpdateGate`** ([`main.dart`](../lib/main.dart) home widget) calls `AppUpdateService.checkForUpdate()`
2. Service GETs `AppConfig.updateManifestUrl` with `Cache-Control: no-cache`
3. Manifest JSON parsed (supports `Map`, raw JSON `String`, UTF-8 BOM strip)
4. **`version_code`** compared using `normalizeVersionCode()` (strips ABI prefix from split APK builds, e.g. `2041` → `41`)
5. If remote > installed → **`AppUpdateScreen`** (non-dismissible when `force_update: true`)
6. User taps **Download update** → progress bar with size/percentage
7. SHA-256 verified after download
8. Native Android install intent via `ApkInstallerChannel` + FileProvider
9. **`PackageReplacedReceiver`** relaunches app after successful install

If manifest fetch fails: **Retry** or **Continue offline** (user choice).

Interrupted downloads are **discarded**; next cold start restarts download from zero.

---

## Manifest format (`ota/manifest.json`)

```json
{
  "app_id": "com.pphl.employee_attendance",
  "version_name": "2.2.3",
  "version_code": 41,
  "force_update": true,
  "release_notes": "Describe changes for users",
  "published_at": "2026-08-12T10:56:55Z",
  "apks": {
    "arm64-v8a": {
      "url": "https://github.com/ciphercall/rocket-launcher/releases/download/v2.2.3-build41/app-arm64-v8a-release.apk",
      "size_bytes": 47925422,
      "sha256": "85013a39d3748c0b69b3a1120b44bcd4ce50b764604741fb938dc241d9645b63"
    },
    "armeabi-v7a": {
      "url": "https://github.com/.../app-armeabi-v7a-release.apk",
      "size_bytes": 40197422,
      "sha256": "..."
    }
  }
}
```

- **`version_code`**: base build number (not ABI-offset). Publisher normalizes via `Read-ApkVersion.ps1`.
- **`force_update`**: when `true`, no skip — user must update or continue offline on fetch errors only.
- Release tag format: `v{version_name}-build{version_code}` (e.g. `v2.2.3-build41`).

---

## Compile-time configuration

| Dart define | Default | Purpose |
|-------------|---------|---------|
| `UPDATE_MANIFEST_URL` | `https://raw.githubusercontent.com/ciphercall/rocket-launcher/main/ota/manifest.json` | Manifest fetch URL |
| `UPDATE_CHECK_ENABLED` | `true` | Set `false` to skip OTA gate (local dev) |

Set in [`app_config.dart`](../lib/config/app_config.dart). Production builds pick up `UPDATE_MANIFEST_URL` from `github.env` via [`build-production-apk.ps1`](../scripts/build-production-apk.ps1).

Dev example:

```powershell
flutter run --dart-define=UPDATE_CHECK_ENABLED=false
```

---

## Android permissions & native code

| Item | File |
|------|------|
| `REQUEST_INSTALL_PACKAGES` | `android/app/src/main/AndroidManifest.xml` |
| FileProvider for APK URI | `android/app/src/main/res/xml/file_paths.xml` |
| Install + ABI detection | `android/.../ApkInstallerChannel.kt` |
| Relaunch after update | `android/.../PackageReplacedReceiver.kt` |

User must allow **Install unknown apps** for this app if Android prompts.

---

## Version display

Profile screen shows `v{version}+{build}` with ABI-offset normalization (split APK `versionCode` like `2041` displays as `+41`).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| App opens normally, no update | Manifest `version_code` ≤ installed build | Publish newer build; force-close app before retest |
| "Could not read update manifest" | Network, parse error, wrong URL | Tap Retry; open manifest URL in phone browser; check `github.env` |
| Download fails | Slow/blocked GitHub | Retry; try mobile data vs Wi‑Fi |
| Install dialog missing | Install permission denied | Settings → Apps → allow install unknown apps |
| Update screen on v39 after fix | Old APK without parse fix | Manually install latest baseline once (v40+) |
| Publish fails: missing PAT | Empty `GITHUB_PAT` | Fill `config/github.env` or set `$env:GITHUB_PAT` |

---

## Verification checklist

After publishing build **N**:

1. Manifest shows `"version_code": N` at the raw URL
2. [Releases page](https://github.com/ciphercall/rocket-launcher/releases/latest) has both APK assets
3. Phone on build **N−1**: cold start → update screen → download → install → Profile shows **N**
4. Phone on build **N**: cold start → app enters normally

**Verified on real device:** August 12, 2026 — v40 → v41 OTA test successful. Later builds: v41 → v42. **v2.2.3+43** = Receive payment + Post booking UX (sales web create-page layouts). **v2.2.3+44** = Post Booking chicks Zone dropdown from `all-dealer-lists` `zoneList`. **v2.2.3+45** = Face registration/check-in 2 s positioning window + ~1 s hold before auto-capture. **v2.2.3+46** = Home Hours same-day duration (fix 24h extra). **v2.2.3+47** = Vehicles trip list from `get-trips-list`. **v2.2.3+48** = Vehicles fleet list, then Maintenance and Trips per vehicle. **v2.2.3+50** = Geo Tracking OSM layer switcher. **v2.2.3+51** = Geo Tracking native Google Maps (Standard / Terrain / Hybrid Satellite). **v2.2.3+52** = Stricter face placement on registration and check-in, plus a prompt to re-register if face data is missing. **v2.2.3+53** = Face registration and check-in wait until the face fills the oval before capturing. **v2.2.3+54** = Face guide is a rounded square that matches the corner frame.

---

## Related docs

- [`rocket launcher/README.md`](../../rocket%20launcher/README.md) — publisher scripts and GitHub API flow
- [`SERVER_COMMANDS.md`](../../SERVER_COMMANDS.md) — workspace command reference (OTA section)
- [`MOBILE_EMPLOYEE_FEATURES.md`](MOBILE_EMPLOYEE_FEATURES.md) — feature summary including OTA
