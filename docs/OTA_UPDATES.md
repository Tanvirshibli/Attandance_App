# OTA (Over-The-Air) Updates — PPHL Attendance App

Last updated: November 10, 2026

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

## Channels

Two OTA channels: **prod** (default) and **beta**. Each has its own manifest file in the `rocket-launcher` repo and its own version-number band.

| Channel | Manifest | Version name | Build number | Force update | Release tag |
|---|---|---|---|---|---|
| `prod` | `ota/manifest.json` | `2.6.0` | 100–8999 | yes | `v2.6.0-build108` |
| `beta` | `ota/beta/manifest.json` | `2.6.0-beta.1` | 9000–9999 | **no** | `v2.6.0-beta.1-build9001-beta` |

### ⚠️ The version bands are the whole design

`version_code` is a plain integer compare in `app_update_service.dart` — there is nothing channel-aware in the comparison itself. Separate manifest URLs therefore do **not** keep the channels apart on their own:

```
beta published at 110 while prod is at 109
  → every production phone is offered the beta APK
```

So the build numbers occupy **disjoint ranges**. A prod build can never exceed a beta build, which means a beta manifest is never "older" than a production one and a production device is never offered a beta.

`normalizeVersionCode` is band-aware to support this. It strips Flutter's split-per-ABI prefix (1000 / 2000 / 3000) but **only** for values in 1000–3999 — anything higher is a real version code. Left as `raw % 1000`, a beta build 9108 would become 108 and compare as an early production build.

`build-production-apk.ps1` puts beta numbers at/above 9000 and `publish-update.ps1` **refuses** a build number in the wrong band before uploading anything, because the failure would otherwise only show up in the field.

### Publishing

```powershell
# production (default)
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Publish -ReleaseNotes "..."

# beta
powershell -ExecutionPolicy Bypass -File .\scripts\build-production-apk.ps1 -Channel beta -Publish -ReleaseNotes "..."
```

`-Channel beta` sets `--dart-define=UPDATE_CHANNEL=beta`, points the build at `ota/beta/manifest.json`, writes the version name as `X.Y.Z-beta.1`, and copies the APKs to `rocket launcher\inbox\beta\` so a beta build cannot be picked up by a later prod publish.

Beta is **not** a forced update — a tester must be able to walk away from a bad build.

### Seeing which channel you are on

- **Profile → Update channel** — only rendered on a beta build, below About.
- **Update screen** — a beta manifest shows a "Beta build" pill under the version.
- `adb logcat` shows `OTA channel=... manifest=...` in debug builds.

> **The channel is fixed at compile time.** An installed build cannot be repointed at the other manifest, so switching channels means installing the other channel's APK.

---

## App-side update flow

1. **`UpdateGate`** ([`main.dart`](../lib/main.dart) home widget) calls `AppUpdateService.checkForUpdate()`
2. Service GETs `AppConfig.updateManifestUrl` with `Cache-Control: no-cache`
3. Manifest JSON parsed (supports `Map`, raw JSON `String`, UTF-8 BOM strip)
4. **`version_code`** compared using `normalizeVersionCode()` (strips the ABI prefix from split-APK builds, e.g. `2041` → `41`; leaves the 9000+ beta band intact)
5. If remote > installed → **`AppUpdateScreen`** (non-dismissible when `force_update: true`)
6. User taps **Download update** → progress bar with size/percentage
7. SHA-256 verified after download
8. Native Android install intent via `ApkInstallerChannel` + FileProvider
9. **`PackageReplacedReceiver`** relaunches app after successful install

If manifest fetch fails: **Retry** or **Continue offline** (user choice).

Interrupted downloads are **discarded**; next cold start restarts download from zero.

### Update screen layout

`AppUpdateScreen` splits its `Scaffold` body into two slots: an `Expanded` +
`SingleChildScrollView` holding the header and the changelog, and a
`_buildActionArea()` sibling that always sits at the bottom with the download /
progress / retry control and the force-update caption.

**Keep it that way.** The screen previously used one `Column` with a `Spacer()`
before the button. A `Column` does not clip its children, it overflows them, so
a release note taller than the remaining height pushed the button past the
bottom edge where nothing could scroll to it or tap it. On a `force_update: true`
build the user cannot leave the screen, so that overflow stranded them on the
screen with no way forward.

Two consequences worth remembering:

- **Any control that is the only way forward must be outside the scroll view.**
  Not in its last slot — outside it.
- **Do not reintroduce a `Spacer()`** inside the scrolling `Column`. It expands
  to fill the leftover space and undoes the pinning.

`test/app_update_screen_layout_test.dart` guards this: with ~40 paragraphs of
notes on a short viewport it asserts the button is found, is tappable, and that
no `RenderFlex` overflow occurs. 6 of its 8 cases fail against the old
single-`Column` layout.

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
| `UPDATE_CHANNEL` | `prod` | `prod` or `beta` — picks the manifest path. See [Channels](#channels) |
| `UPDATE_MANIFEST_URL` | derived from the channel | Overrides the manifest URL entirely (tunnel / one-off builds) |
| `UPDATE_CHECK_ENABLED` | `true` | Set `false` to skip OTA gate (local dev) |

Set in [`app_config.dart`](../lib/config/app_config.dart). [`build-production-apk.ps1`](../scripts/build-production-apk.ps1) passes `UPDATE_CHANNEL` and the matching `UPDATE_MANIFEST_URL` from `-Channel`; the URL is derived from `OTA_BASE_URL` in `github.env` (or `GITHUB_OWNER`/`GITHUB_REPO`/`GITHUB_BRANCH`), not read from the flat `UPDATE_MANIFEST_URL` key — that key is prod-only and a beta build reading it would watch the production feed.

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

Profile screen shows `v{version}+{build}` with ABI-offset normalization (split APK `versionCode` like `2041` displays as `+41`). The offset is derived from the ABI of the **installed APK**, not from `Build.SUPPORTED_ABIS`: on a 64-bit phone running the armeabi-v7a split the two disagree, and using the preferred one left the number unnormalised (`+1120`), which is both a wrong label and a version comparison that never offers an update.

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

> **Raw URLs cache.** `raw.githubusercontent.com` can serve a stale manifest for a
> minute or two after the manifest commit lands. If the manifest still shows the
> old `version_code`, re-request with a cache-busting query string
> (`…/manifest.json?nocache=<date>`) before concluding the publish failed — and
> check `git log origin/main` in `ciphercall/rocket-launcher` for an
> `OTA release <version>` commit, since that is the authoritative signal.

> **Published build** v2.4.0+95 → tag `v2.4.0-build95`, manifest commit
> `3fa6406`. Both split APKs verified by download: byte counts and SHA-256 match
> the manifest exactly, `versionName=2.4.0` / `versionCode=2095` per `aapt2`,
> `arm64-v8a` only in that asset.

**Verified on real device:** August 12, 2026 — v40 → v41 OTA test successful. Later builds: v41 → v42. **v2.2.3+43** = Receive payment + Post booking UX (sales web create-page layouts). **v2.2.3+44** = Post Booking chicks Zone dropdown from `all-dealer-lists` `zoneList`. **v2.2.3+45** = Face registration/check-in 2 s positioning window + ~1 s hold before auto-capture. **v2.2.3+46** = Home Hours same-day duration (fix 24h extra). **v2.2.3+47** = Vehicles trip list from `get-trips-list`. **v2.2.3+48** = Vehicles fleet list, then Maintenance and Trips per vehicle. **v2.2.3+50** = Geo Tracking OSM layer switcher. **v2.2.3+51** = Geo Tracking native Google Maps (Standard / Terrain / Hybrid Satellite). **v2.2.3+52** = Stricter face placement on registration and check-in, plus a prompt to re-register if face data is missing. **v2.2.3+53** = Face registration and check-in wait until the face fills the oval before capturing. **v2.2.3+54** = Face guide is a rounded square that matches the corner frame. **v2.2.3+55** = One centered face frame (no overlapping boxes). **v2.2.3+56** = Registration advances after a saved capture; live fill and still size use the same 16% floor. **v2.2.3+57** = Success tick centered in the face guide; step/coaching text centered above the frame. **v2.2.3+58** = Face-guide tick on the painted rect; capture screens stay awake; Geo Tracking full-screen map. **v2.2.3+59** = Farm & Dealer forms collect the full Phase-1 field set; searchable ID dropdowns. **v2.2.3+60** = Farm visit report form; Farm & Dealer hub Create and View All cards. **v2.2.3+61** = Farms, Dealers and Markets hub with top-5 previews and compact Create/View-all icon buttons. **v2.2.3+63** = Colorful hub section panels; Recent Attendance card layout fix; farm visit free-text fields with demo chips and paper-aligned units/extra_data. **v2.2.3+72** = Searchable dropdown overlay list on field tap (not Autocomplete). **v2.2.3+71** = Searchable form dropdowns open options list on field tap. **v2.2.3+70** = Marketing photo serve fix; visit detail with photos; API-first dealer/market forms; tap-outside dismiss on searchable fields. **v2.2.3+68** = Farm visit detail photo thumbnails; combined Production%/FCR field on form. **v2.2.3+66** = Separate farm/dealer/market visit forms; farm report autocomplete fields; read-only dealer info on farm visit. **v2.2.3+64** = Markets hub panel purple (`AppColors.secondary`) so Dealers (blue) and Markets are visually distinct.

---

## Related docs

- [`rocket launcher/README.md`](../../rocket%20launcher/README.md) — publisher scripts and GitHub API flow
- [`SERVER_COMMANDS.md`](../../SERVER_COMMANDS.md) — workspace command reference (OTA section)
- [`MOBILE_EMPLOYEE_FEATURES.md`](MOBILE_EMPLOYEE_FEATURES.md) — feature summary including OTA

---

## November 14, 2026 Update (v2.5.4+122) — main channel

**A phone on the 32-bit build was told it was already up to date, so no update ever arrived.**

> Published from `2.5.4+120` → `2.5.4+122` (build 121 was consumed by a failed Kotlin compile and never published). Tag `v2.5.4-build122`. Checked after publishing: `version_code` 122 in the manifest and both `arm64-v8a` and `armeabi-v7a` APK entries present with sizes and SHA-256; both assets downloaded and their `libapp.so` and `classes.dex` carry the new `getInstalledAbi` call.

- **Root cause: the wrong ABI's offset.** A split APK's `versionCode` is `base + offset` (armeabi-v7a +1000, arm64-v8a +2000). The update check subtracted the offset of the *device's preferred* ABI, not of the APK actually installed. A 64-bit handset running the armeabi-v7a split therefore reported `1120`, `normalizeVersionCode` subtracted nothing (1120 is below arm64's 2000), and `120 > 1120` is false — "up to date" on every cold start, forever. Profile showed the same mistake as `+1120`
- **Fix:** a new `getInstalledAbi` platform call (`Process.is64Bit()` paired with `Build.SUPPORTED_ABIS`, because `ApplicationInfo.primaryCpuAbi` is `@hide`) reports the installed APK's ABI, and both the update check and the Profile version label use it. `getPreferredAbi` keeps its own job — choosing which APK to download
- **Devices already on an older 32-bit build must install this one by hand once.** The faulty comparison lives in the installed build, so it cannot be delivered to itself; after one manual install, OTA works normally
- Guard: `test/ota_channel_test.dart` gains an "installed ABI offset" group pinning `1120` + armeabi → `120`, the same number + arm64 → `1120` (the failure), and that build 121 is offered to a phone on the 32-bit split

**Pubspec stays on the prod line at `2.5.4+122`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 14, 2026 Update (v2.5.4+120) — main channel

**The underline under the offline screen's text is gone.**

> Published from `2.5.4+119` → `2.5.4+120`. Tag `v2.5.4-build120`. Checked after publishing: `version_code` 120 in the manifest and both `arm64-v8a` and `armeabi-v7a` APK entries present with sizes and SHA-256.

- **Root cause: no `Material` ancestor.** Flutter's fallback text style when nothing above a `Text` supplies a Material is the debug "missing Material" style — `TextDecoration.underline`, double style, yellow. Every screen gets its Material from a `Scaffold`; this overlay is mounted in `MaterialApp.builder`, beside the Navigator rather than inside a route, so it inherited none and every line of the card rendered double-underlined. A `Material(type: MaterialType.transparency)` now wraps the card: it supplies the theme's real text style and paints nothing, so the card's own gradient stays visible
- **Guard:** `test/connectivity_guard_test.dart` gains "the overlay brings its own Material", which asserts the resolved style carries no underline *and* that the nearest Material above the headline is the overlay's own transparent one. It fails against `+119` with `Expected: not TextDecoration.underline / Actual: TextDecoration.underline`
- No change to the artwork, the copy, or the detection timings from `+119`

**Pubspec stays on the prod line at `2.5.4+120`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 14, 2026 Update (v2.5.4+119) — main channel

**The offline screen is now built around a large animated signal mark, and a dropped connection is
noticed in about a second and a half instead of up to nine.**

> Published from `2.5.4+118` → `2.5.4+119`. Tag `v2.5.4-build119`. Checked after publishing: `version_code` 119 in the manifest and both `arm64-v8a` and `armeabi-v7a` APK entries present with sizes and SHA-256.

- **Detection latency was the real defect, not the drawing.** A drop cost up to ~9 s: a 3 s poll tick, a 3 s TCP timeout, then a second sample on the next tick. The timeout is now 800 ms, the online interval 1.5 s (offline retry 1 s), and the confirming sample runs on its own timer the moment the first one fails. A refusal (errno 101/111/113 — airplane mode, a pulled link) confirms at once; an ambiguous timeout waits 250 ms so one congested handshake cannot count twice. Typical case ≈ 1.5-2 s, silent blackhole ≈ 3.5 s
- **The two-failure tolerance is unchanged.** Only *how fast the second sample arrives* changed, never that one is skipped, so a single dropped packet still does not blur the screen mid-punch. The poll tick is suppressed while a confirm is pending, so one real drop cannot satisfy the rule by itself
- **`OfflineOverlay` is an artwork-led screen.** A 176 dp signal cluster — two expanding pulse rings 2.6 s apart, a slow 9 s orbiting accent dot, and a 96 dp disc holding a 42 dp Phosphor duotone cloud-slash with a warm halo — sits above deliberately small type (headline 17, body 13, caption 11). It uses `AppType`/`AppColors`/`AppSpace`/`AppRadius` and Phosphor icons instead of the raw `TextStyle`s and Material icon it shipped with in `+118`, and the copy drops the em dash: "Check your connection. This screen closes automatically when you're back online."
- **Motion and access.** Only transform and opacity animate; the halo pulse is a second controller on the icon's own layer, a `RepaintBoundary` wraps the card, and the blur sigma is constant. `MediaQuery.maybeDisableAnimationsOf` drops both repeating loops on devices with animations off, and `Semantics(liveRegion: true)` announces the state
- Guard: `test/connectivity_service_test.dart` gains a "detection latency" group (confirm-without-tick, refusal fast path, timeout delay, no double count); all four fail if the confirm probe is removed. `test/connectivity_guard_test.dart` is unchanged and still passes

**Pubspec stays on the prod line at `2.5.4+119`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 14, 2026 Update (v2.5.4+118) — main channel

**The app blurs itself when the phone is really offline, and comes back on its own.**

> Published from `2.5.4+117` → `2.5.4+118`. Tag `v2.5.4-build118`. Checked after publishing: `version_code` 118 in the manifest and both `arm64-v8a` and `armeabi-v7a` APK entries present.

- **A global foreground connectivity guard wraps the app.** `ConnectivityService` (`lib/services/connectivity_service.dart`) probes real reachability with `Socket.connect` (3 s timeout) against the app's own backend hosts from `AppConfig.authApiBaseUrlCandidates`, falling back to the attendance hosts — online if any host accepts. It samples every 3 s while online and 2 s while offline, needs two consecutive failures before reporting offline, and restores online on the first success so a single dropped packet does not blur the screen. Sampling runs only in the foreground (`resumed` starts it; `paused` / `inactive` / `detached` stop it)
- **`ConnectivityGuard`** (`lib/widgets/connectivity_guard.dart`) is mounted in `MaterialApp.builder` **outside** the existing `LocationGuard`. Offline it renders a `Stack` with the app under `IgnorePointer` plus `OfflineOverlay`, wrapped in `PopScope(canPop: false)`, so no tap, drag, text-field focus or Android back press reaches the app. The child widget instance is passed through unchanged, so the current screen, its scroll position, typed form input and route stack survive the transition without a reload
- **`OfflineOverlay`** (`lib/widgets/offline_overlay.dart`) is the blurry screen: `BackdropFilter` at constant sigma 10 over a 55% black scrim, a 250 ms entry (scrim fade + panel rise), a repeating pulse on the icon only, the headline "Can't connect to the internet" and the line "Check your connection — this screen will close automatically when you're back online." It has no button on purpose — nothing is tappable while offline and recovery is automatic
- **No connectivity plugin was added.** `connectivity_plus`-style plugins only report whether a network interface exists (wifi with a dead upstream or a captive portal still reads as connected) and each one needs a native plugin in the APK. The TCP probe tests actual reachability, adds no native payload so the 32-bit build does not grow, and sends no HTTP request to the PHP app or database — a handshake only. Dev builds that probe production hosts (emulator, Cloudflare tunnel) disable it with `--dart-define=CONNECTIVITY_GUARD_ENABLED=false`, alongside the existing `UPDATE_CHECK_ENABLED`
- Guard: `test/connectivity_service_test.dart` and `test/connectivity_guard_test.dart`

**Pubspec stays on the prod line at `2.5.4+118`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 10, 2026 Update (v2.5.4+116) — main channel

**The update check cannot be answered from a cache any more, and it can be run on demand.**

> Published from `2.5.4+115` → `2.5.4+116`. Tag `v2.5.4-build116`. **This release also diagnosed a live delivery problem:** minutes after `+116` was published, the manifest URL returned the `+115` document while the repository and the local publisher manifest already held `+116`, and the same URL with a query string returned `+116`. `raw.githubusercontent.com` is CDN-served and ignores the request's `Cache-Control`, so a phone — or an ISP proxy in front of one — can keep reading the previous publish and the app looks like it never received the update.

- **Every manifest request now carries `?ts=<millis>`.** Each check is a URL no cache holds a prior response for, so the newest manifest is always fetched. This is the fix that makes a publish arrive; everything else was already correct
- **Profile → Check for updates** runs the same check on demand and states the outcome plainly: a newer build opens the update screen; otherwise it reports `installed N, latest M (channel prod)`, or the failure text with the channel and manifest URL. The cold-start gate stays silent on failure by design (an offline phone must still open), which is precisely why "no update appeared" had no evidence on the device before this row existed
- `AppUpdateCheckResult` now carries the remote build number, so both numbers in that comparison are visible instead of a bare "up to date"
- **Devices already on a published build receive this one; a device stuck behind the cache needs `app-arm64-v8a-release.apk` (or the armeabi-v7a asset) installed once from the `v2.5.4-build116` release**, after which every future check is cache-proof

**Pubspec stays on the prod line at `2.5.4+116`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 10, 2026 Update (v2.5.4+115) — main channel

**The Farms, Dealers and Markets hub tabs carry the filter bar too.**

> Published from `2.5.4+114` → `2.5.4+115`. Tag `v2.5.4-build115`; the live manifest was verified after publishing (channel `prod`, `version_code` 115, `force_update` true, both APK entries present with sizes and SHA-256).

- **The hub is where the module opens**, and its preview grids were unfiltered — the only way to narrow anything was to push into "All farms", "All dealers" or "All markets" first. Each hub tab now shows the same bar above its grid: status, type and area
- Type choices come from the tab's own pool — farm/farmer inside Farms, dealer/outlet inside Dealers, product types inside Markets — instead of a hardcoded list
- Each tab keeps **its own filter state**, so narrowing Dealers does not follow the officer onto Markets and back
- A grid emptied by filters reads "No … match these filters" and offers `Clear filters`; the "nothing recorded yet" copy still wins when the pool itself is empty
- Guard: none added this round — the predicates are the ones pinned by `test/marketing_filters_test.dart` in `+114`

**Pubspec stays on the prod line at `2.5.4+115`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 10, 2026 Update (v2.5.4+114) — main channel

**Every marketing list gets one filter bar: status, type, date range and area.**

> Published from `2.5.4+113` → `2.5.4+114`. Tag `v2.5.4-build114`; the live manifest was verified after publishing (channel `prod`, `version_code` 114, `force_update` true, both APK entries present with sizes and SHA-256).

- **One shared bar replaces the ad-hoc chips.** Each screen shows a `Filters` pill with an active-filter count, a pill per dimension it offers (carrying the chosen value), and an animated `Clear all`. A pill opens its own bottom sheet; the `Filters` pill opens them all with a single Apply
- **Dimensions:** status + existing search everywhere; type (party, product, visit or survey) where the entity has one; date (`All / Today / This week / This month / Custom`, custom inclusive); area (the employee's own zones) where rows carry a zone. Farms/dealers get status + type + area, markets status + product type + area, a market's party list status + type, the visits tab status + type + date, follow-ups status + date, and the visit list all four
- **Nothing refetches on a filter change.** No marketing list endpoint paginates or accepts a date range / visit type, so narrowing happens over the payload the screen already holds. The visit list still sends `status` because it always did
- **A locked Farms/Dealers entry keeps its type** through `Clear all` and never reports it as an active filter, and a farm's report statuses/types are derived from its own rows rather than a hardcoded list
- **Filtered dead ends are distinct from empty lists:** they say no rows match and offer `Clear filters`; the "create one to get started" copy still takes precedence when the list is genuinely empty
- Guard: `test/marketing_filters_test.dart` pins the predicates (date presets, `yyyy-MM-dd` vs ISO input, fail-open on `All`, `done` ≡ `completed`, multi-valued product types, area matching, active count)

**Pubspec stays on the prod line at `2.5.4+114`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 10, 2026 Update (v2.5.4+113) — main channel

**The face registration screen follows the Bangla toggle.**

> Published from `2.5.4+112` → `2.5.4+113`. Tag `v2.5.4-build113`; the live manifest was verified after publishing (channel `prod`, `version_code` 113, `force_update` true, both APK entries present with sizes and SHA-256).

- **Re-registering a face stayed English** while the check-in capture screen followed the toggle: the string set covered only the check-in flow. The registration screen now reads the same persisted preference, so its status lines, angle names and instructions, different-person dialog, step/progress labels, tips and action labels all switch with it
- Its coaching icon matched English keywords, which stopped matching once the copy was Bangla; it compares against the same string object now, as check-in does
- The shared capture stage accepts a Bengali font fallback for the coaching line: Poppins has no Bengali coverage, so the fallback chain carries those glyphs instead of leaving them to the device's default stack
- Deep verification diagnostics (face-quality and sharpness reports) remain English by design — they are technical failure reports, not placement guidance

**Pubspec stays on the prod line at `2.5.4+113`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## November 10, 2026 Update (v2.5.4+112) — main channel

**Check-in closes after the grace window, the capture screen speaks Bangla, and the preview shows placement state around the guide.**

> Published from `2.5.4+111` → `2.5.4+112`. Tag `v2.5.4-build112`; the live manifest was verified after publishing (channel `prod`, `version_code` 112, `force_update` true, both APK entries present with sizes and SHA-256). Release notes are the user-facing text carried in the manifest.

- **A self check-in now closes 15 minutes after the shift start.** The dashboard refuses it before the camera opens and the capture screen re-checks before submitting, so a screen left open past the deadline cannot post a punch. Check-out is unaffected. The rule mirrors the server guard exactly (`CHECK_IN_GRACE_MINUTES`, the `now > deadline` boundary, and the night-shift day rollback) and fails open when HRM holds no shift for the employee
- **The preview outside the face guide is tinted** with the same colour the border uses (idle grey, orange off-position, teal placed, green verified) at very low alpha. The guide square is still never filled — the face window stays untouched — and the underlying dim was lowered from 0.48 to 0.20 so the coaching strip stays legible
- **Face capture can be switched to Bangla** from Profile → Settings. Every string on the check-in/check-out capture screen follows the toggle (coaching, challenge names, instructions, buttons, error card); the face-registration screen stayed English in this build and follows the toggle from `2.5.4+113`, as do deep verification diagnostics. The flag persists in `SharedPreferences` and applies to the next capture without a restart
- Guard: `test/check_in_window_test.dart` pins the window cases (inside, exact deadline, one minute late, night shift, fail-open on missing or malformed shift values)

**Pubspec stays on the prod line at `2.5.4+112`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## October 15, 2026 Update (v2.5.4+111) — main channel

**Location tracking keeps working while the app is closed. Force update.**

> Published from `2.5.4+110` → `2.5.4+111`. Tag `v2.5.4-build111`; the live manifest was verified after publishing (channel `prod`, `version_code` 111, `force_update` true, both APK entries present) and each asset was range-requested — served as a real ZIP archive (PK magic), sizes matching the manifest exactly. Release notes are the user-facing text carried in the manifest.

- **Closed-app tracking captured nothing before this release**: the 15-minute WorkManager job and the FCM `geo_wake` push both run in a fresh isolate, where the in-memory permission gate was always empty — every background capture silently no-op'd for every user, and the FCM handler additionally dropped every wake push on a UI-isolate-only flag. The permission snapshot is now persisted and rehydrated on demand, the wake handler gates on `Firebase.apps` + the same SharedPreferences the worker reads, and background captures get a 45-second fix budget with a last-known-position fallback
- Uploads resolve the employee id from a persisted mirror instead of a live profile fetch, and duplicate observations are coalesced so an upload can only mark its own queue entry
- Logout drops the session's employee id, pending ping queue and last-ping mirror, and disables the device's server-side geo registration — previously the ZKTeco sender kept waking signed-out devices. A profile fetch or token refresh completing mid-logout can no longer re-persist the dead session
- Guard: `test/geo_isolate_wake_test.dart` pins the wake truth table and the fail-closed isolate gate; `test/permission_snapshot_test.dart` pins snapshot round-trip and clear semantics; the permission widget tests now mock SharedPreferences

**Pubspec stays on the prod line at `2.5.4+111`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## October 10, 2026 Update (v2.5.4+110) — main channel

**Chick booking temporarily disabled. Force update.**

> Published from `2.5.4+109` → `2.5.4+110`. Tag `v2.5.4-build110`, manifest commit `2668c38`; both APKs verified by download — sizes and SHA-256 match the manifest, `versionName=2.5.4`, `versionCode=2110` (→ 110), and the APK bakes the **prod** manifest URL with no beta path.

- **Chick booking posting is hidden and disabled** while the chick booking flow is reworked: the Module picker is gone from Post booking (feed is the only module), and `SalesService.createBookingPersonBook` rejects any non-feed module before any network call. Feed booking, Sales Info reporting and every other sales feature are unchanged
- Gated by the deployment-wide feature flag `sales.chicksBooking.enabled` — local fallback `false`, so it fails closed on every server response and offline device. Flip the flag on the app-config endpoint to re-enable without another release; the implementing release flips the local default when the rework lands
- Guard: `test/chicks_booking_gate_test.dart` pins the fail-closed rejection (a chicks request is rejected with zero endpoint resolves, while a feed request still reaches the endpoint resolve); `test/endpoint_config_test.dart` pins the flag's fail-closed resolution

**Pubspec stays on the prod line at `2.5.4+110`** after this release (the beta line is paused at `2.5.3-beta.1+9036`).

---

## October 7, 2026 Update (v2.5.3+109) — main channel

**Voice-typing language popup fix. Force update.**

> Published from `2.5.3+108` → `2.5.3+109`. Tag `v2.5.3-build109`, manifest commit `5457b1f`; both APKs verified by download — sizes and SHA-256 match the manifest, `versionName=2.5.3`, `versionCode=2109` (→ 109), and the APK bakes the **prod** manifest URL with no beta path.

- The mic's language popup was a Material radio group dismissed from the group's `onChanged`; tapping the radio that was **already selected** reports `false`, which `RawRadio` ignores — a dead tap that left the dialog open, so re-picking the current language did nothing and the officer had to switch languages and toggle the mic twice
- The popup is now a **ticked pick-and-start list**: every option starts a session, including the language already in use; the current one is bold with a check mark. Dictation, locale resolution and biasing phrases are unchanged
- Guard: `test/voice_language_popup_test.dart` fails against the old popup on the dialog staying open (verified by stashing the fix)

**Beta line re-seated at `2.5.3-beta.1+9036`** after this release (next beta = 9037), same as the 108 release.

---

## October 7, 2026 Update (v2.5.3+108) — main channel

**The first main-channel release since the beta channel was introduced. Force update.**

> Published from `2.5.3+107` (prod line) → `2.5.3+108`. Tag `v2.5.3-build108`, manifest commit `9ca974f`; both APKs verified by download — sizes and SHA-256 match the manifest, `versionName=2.5.3`, `versionCode=2108` (→ 108), and the APK bakes the **prod** manifest URL with no beta path.

Covers everything the beta line shipped between `2.5.2-beta.1+9009` and `2.5.3-beta.1+9036`:

- **Face attendance** — face alignment + GhostFaceNet 512-d recognition; stricter identity matching so a shared account cannot match several people; the registration-stickiness fix; instant check-in/check-out (dashboard returns on match, the punch finishes in the background with a sync pulse). Everyone re-enrols their face once on this update
- **Marketing** — company master from the mobile backend (93 curated + Sales gaps); search-first Add Farm / Add Dealer / Add Market screens; sector removed from the dealer, market and visit forms (markets are picked directly); product-company pickers follow the product category; ERP dealer integration (parent-dealer picker, code fill, farm-report details); `outlet`/`farmer` parties appear in their lists again; dealer/farm detail pages gained **Visits / Follow-ups tabs**; the dealer-visit server-error fix (`client_uuid` UUID v4); **photos everywhere** (grid covers, row thumbnails, detail strips)
- **Bookings** — any employee can post a feed/chicks booking without a sales account; Post sale entry hidden

**Beta line resumed at `2.5.3-beta.1+9036`** (commit `497c513`) after this release: the publisher's beta band floor is `9000 + (build % 100)`, so leaving the pubspec on the prod line would have produced 9009 next — below the live beta build — and silently withheld the next beta from testers.

---

## September 30, 2026 Update (v2.4.0+94)

**Full-screen marketing grids, employee-scoped forms, generated codes:**

- **Farms, Dealers and Markets** is now one **full-height grid per tab** instead of three stacked cards showing five rows each. The cards, the 5-row preview and the fixed 268 dp tab body are gone; the grid takes every remaining pixel, scrolls on its own and pulls to refresh per tab
- Create / View-all moved to a **bar pinned under the tabs**, re-labelled on swipe so the pills name the tab on screen. **Follow-ups** joined that bar as an icon tile instead of taking a row of grid height
- Lists are fetched with `limit: 200` instead of the API default of 100 — a grid is only worth having with more rows than that
- **Zone, company, sector and market are now derived from the logged-in employee** and shown read-only on the dealer, farm and market forms. A field officer no longer records their own territory by hand, which was the easiest way to file a record under the wrong zone
- **Market** is the one *nearest the form's own GPS fix* among the markets in the zone, not the first row — a zone usually holds several, and the officer is the one who knows which they are standing in. It stays read-only but visible, so a mis-resolution can be reported
- Anything unresolved is **omitted from the payload** rather than guessed. A wrong `company_id` is a silent data error; an empty column an admin can correct. A dealer with no resolvable zone is blocked from submitting
- **Codes are generated by the server** (`DLR-09260001`, `FMR-…`, `MRK-…`) and shown read-only, so two officers opening a form in the same second cannot be handed the same code
- **Party type offers two options**: New dealer / Existing dealer. Phone is **required and unique** per dealer and per market — checked on a 700 ms debounce while typing and again on submit, comparing normalised digits so `01712-345678` and `+8801712345678` are one number
- Markets gained a **phone field** and a **photo gallery**
- New shared UI component `ReadOnlyField` — a derived value rendered as a settled fact, with a lock glyph rather than a dropdown that looks tappable

Backend: ZKTeco gains `next-code` endpoints (sequence allocated under a row lock), a conditional `unique` phone rule on parties and markets, `mkt_markets.phone`, and `market` as an attachment type. See `docs/MARKETING_MOBILE_API.md` and [FARM_DEALER_MOBILE.md](FARM_DEALER_MOBILE.md).

---

## September 29, 2026 Update (v2.3.0+93)

**Tabbed marketing hub + labelled pill actions:**
- **Farms, Dealers and Markets** is now a **three-tab page** instead of three stacked cards. Farms opens first; each tab shows one module's up-to-5 recent records
- **Follow-ups** moves below the tabs, so it stays reachable from all three
- The Create and View-all buttons were **icon-only 36 dp squares** whose meaning came from a tooltip. They are now **icon + text pills** — "Add farm" / "All farms", "Add dealer" / "All dealers", "Add market" / "All markets"
- Party detail's **Post a visit** and **New follow-up** are pills too, replacing a mismatched full-width button beside a 48 dp icon square. New follow-up also had no label or tooltip at all
- New shared UI component `AppPillButton`: 44 dp minimum height, filled for the primary action and tonal for the secondary beside it, with a `dense` variant
- The hub card's action row is a `Wrap`, so the longest label pair falls to a second line instead of overflowing on a narrow handset
- Zone scoping (v2.3.0+92) is unchanged; the zone note now sits above the tab bar

Backend: none. No API, payload or zone-scoping change.

---

## September 29, 2026 Update (v2.3.0+92)

**Zone scoping:**
- Marketing lists, form pickers and dealer dropdowns are now narrowed to the zones the employee is assigned. An employee in several zones sees the **union** of their data — there is no zone switcher
- **Root-cause fix:** HRM returns `user.zoneId` as a jsonb **array**, but the app parsed it as a scalar, so `int.tryParse("[1,2,3]")` produced `null` and **no zone filter was ever sent**. Zone scoping was inert. The profile now reads `zoneIds` as a list
- Zone names and districts come from the new Sales `GET /api/get-zone` (public). HRM carries ids only, so the app joins the two and caches the result for 24 h
- Rows are matched on zone id, zone **name**, or the districts of an assigned zone — so markets, parties and dealers created before zone tagging (`zone_id` NULL) are still visible
- **Zones are joined by name across systems, never by id.** HRM, Sales and ZKTeco assign zone ids independently
- Marketing hub shows a strip naming the employee's zones and their districts; empty lists name the zones instead of looking broken
- Market and party create forms take their zone options from `get-zone` and pre-seed the employee's first assigned zone, matched by name
- Post sale, Post booking and Receive payment dealer dropdowns are scoped by zone name
- The market form previously had no profile prefill while the party form did; both now do
- New files: `lib/models/zone_models.dart`, `lib/models/zone_scope.dart`, `lib/services/zone_scope_service.dart`

**Behaviour when zones are not configured:** an employee with no zones, or an unreachable zone master, sees unfiltered lists exactly as before — no blank screens, no crash.

Backend: HRM `pphl_erp` supplies `user.zoneId` (jsonb array, no names); Sales supplies the zone master and districts. See `docs/FARM_DEALER_MOBILE.md#zone-scoping` and `docs/SALES_AND_PAYMENTS_API_CONTRACT.md` §C.4.

---

## September 25, 2026 Update (v2.3.0+86)

- **Payment receive** — the receipt photo is now **optional**; payments can be posted with no image. Photos that are attached upload as WebP `image[i]` fields index-aligned with `payments[i]`.

---

## September 25, 2026 Update (v2.3.0+85)

**Field-app modernization release:**

- **Login errors** — wrong credentials now show a plain "The provided credentials are wrong."; other auth/network failures map to short friendly messages (raw diagnostics stay in logs).
- **Faster face check-in** — match threshold 0.80 → 0.60 (strong 0.72, adaptive-enroll 0.75), early verification after the first passed challenge, shorter hold/positioning windows.
- **Attendance counts fixed** — home/history/report now reconcile HRM "absent" days against actual ZKTeco punch records (rejected punches excluded).
- **Market survey rework** — "Market visit" flow removed; markets are editable market surveys (`PUT /markets/{id}`) with feed/chicks share %, product types, dealer/farm counts, and competitor rows.
- **Zone hierarchy** — `company > zone > sector` client-side: profile `zoneId` filters market/party/visit lists; dealer create requires a zone.
- **Dealer visit** — autofills market/company/sector from the party, requires a photo, and adds `feed_findings` + `chicks_findings`. Feed unit list includes **Ton**.
- **Voice typing** — mic on every typed field (`speech_to_text`, English/Bangla picker).
- **Universal WebP uploads** — all images compress client-side to WebP and post under `image`/`image[]` (legacy `photos[]` still accepted). Payment receive accepts an optional receipt photo per entry (`image[i]` field, index-aligned).

Backend: ZKTeco `2026_09_01` migration adds zone/market-intel columns; `PUT /markets/{id}` + `zone_id` list filters + `image[]` uploads. See `docs/MARKETING_MOBILE_API.md` (ZKTeco repo) and `docs/FARM_DEALER_MOBILE.md`.

---

## August 26, 2026 Update (v2.2.3+82)

**Face Registration Safety Fix:**
- Face registration screen no longer deletes existing face data on initialization
- Old face data is only deleted after successful new registration completion
- Prevents accidental data loss when users exit the registration screen
- Home screen now shows correct face registration status immediately after registration

**Attendance Button Visibility Fix:**
- Improved attendance record validation in `AttendanceRequestRecord` model
- Added defensive null checks for `requestedInTime` and `requestedOutTime` fields
- Check-in/check-out buttons now render correctly even when backend dump recovery operations leave time fields in inconsistent states
- Fixed null fallback in home screen to show Check In button when no attendance record exists for today
- Backend dump recovery now includes safety checks to validate time format and year ranges before applying changes
