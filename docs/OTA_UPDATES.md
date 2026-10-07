# OTA (Over-The-Air) Updates — PPHL Attendance App

Last updated: October 7, 2026

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
