# Permission-Based Access Control

How HRM role permissions decide what a user can see and do in the Android app.

**Status:** implemented. **Last updated:** October 2026.
**Scope:** `Attandance_App` only — no `pphl_erp` change was needed.

> **Looking for "which permission gates what?"** See
> [PERMISSIONS_REFERENCE.md](./PERMISSIONS_REFERENCE.md) — the per-permission lookup table with the
> exact file and line for every enforcement site. This document is the design, the wire contract and
> the security caveats.

---

## 1. The wire contract

Permissions arrive inside a response the app was **already fetching**.

`GET /api/v1/get-my-info` → `App\Http\Controllers\Api\UserController::getSelf`
(`pphl_erp/app/Http/Controllers/Api/UserController.php:265-317`) resolves:

```
users
  └─ user_has_roles          (many-to-many)
       └─ roles              (roleName, hand-rolled schema — not Spatie)
            └─ role_has_permissions
                 └─ permissions.name
```

and flattens that to a **de-duplicated array of permission-name strings**:

```jsonc
{
  "message": "User get successfully",
  "user": {
    "name": "…", "email": "…", "employee_id": "…",
    "zoneId": [1, 2],
    "isAdmin": "0",            // NOTE: the string "1"/"0", not a boolean
    "isSuperAdmin": "0",
    "permissions": ["farms.read", "farms.create", "markets.read"],
    "roles2": [{ "id": 1, "roleName": "Zone Officer" }]
  }
}
```

Parsed by `AuthUserProfile.fromJson` into `permissions` and `roles`
(`lib/models/auth_user_profile.dart`). A user with no roles gets `permissions: []`
— a real answer, not an error, and distinct from "not fetched yet".

**No endpoint, migration, API-shape change or dependency was added.** The field existed and the app
was discarding it.

### Why permissions cost zero latency

`AppBootstrap._warmAuthenticatedSession()` (`lib/screens/app_bootstrap.dart:119-134`) already fetches
the profile **unawaited**, deliberately, so the first frame is never blocked behind a 45 s request.
`PermissionService.update()` is called on that same result.

```
cold start ──> first frame (shell renders immediately)
                    │
                    └──> get-my-info ──> PermissionService.update() ──> tiles appear
```

There is no extra request and nothing new blocks startup. Widgets watch the service and rebuild once
when the list lands. Between the first frame and the list arriving, gated tiles are **hidden** rather
than shown and then removed.

---

## 2. Where a permission string came from

The strings the app checks are the ones an HRM admin ticks in the role editor on the HRM web client.
Two things about that list are worth knowing, because both are easy to get wrong later:

1. **The list is data, not code.** `pphl_erp` creates permission rows at runtime through
   `POST /api/v1/store/permission`; there is no authoritative seeder (the one that exists,
   `RolePermissionSeeder`, inserts `guard_name` / `module_name` columns its own migrations never
   create). The catalogue can therefore grow without the app being rebuilt.
2. **`farms.*`, `markets.*`, `vehicles.*`, `tracking.*` and `benefits.*` do not exist in any HRM
   permission catalogue in this workspace.** They came from a list that is otherwise a partial excerpt
   of the *accounts* client's `pphl-accounts-client/src/constant/permissions.js` (whose vehicle module
   is `chicksVehicle.*`, and which has no `farms` or `markets` module at all). They must exist as rows
   in the HRM `permissions` table before an admin can grant them — **confirm against production** with
   `GET /api/v1/get_permissions`. If they were renamed, change them in `AppPermissions`, never at a
   call site.

### The rule this forces

`AppPermissions` (`lib/models/app_permissions.dart`) is the single source of truth, and **an
unrecognised string must never throw**. A permission HRM adds tomorrow is inert here; it does not
crash an installed build. A test asserts every catalogue entry is unique and `module.action`-shaped.

---

## 3. The module → permission map

| App module | Visible with | Can create with |
|---|---|---|
| Attendance report | *(ungated)* | — |
| Leave | *(ungated)* | — |
| Payments | *(ungated at the tile)* | — |
| Sales info | *(ungated)* | — |
| **HR benefits** | `benefits.read` | — |
| **Vehicles** | `vehicles.read` | — |
| **Geo tracking** | `tracking.read` | — |
| **Farms & dealers** | `farms.read` **or** `markets.read` **or** `dealer.read` | per tab, below |

Inside **Farms & dealers**, each tab is gated separately:

| Tab | Visible with | "Add …" enabled with |
|---|---|---|
| Farms | `farms.read` | `farms.create` |
| Dealers | `dealer.read` | `dealer.create` |
| Markets | `markets.read` | `markets.create` |

`prInfo.*`, `salesOrder.*`, `liveBirdOrder.*`, `fertilizerOrder.*`, `chicksBooking.*` and
`feedBooking.*` are carried in the catalogue but gate nothing today — this app has no such screens.
They start working the moment one is added.

**Payments** is a deliberate special case: the `PaymentHubScreen` is what the *HR benefits* tile
opens, so it is gated by `benefits.read` rather than a permission of its own. Gating the tile one way
and the screen another would have been incoherent.

**The bottom nav is never gated.** Home, Attendance, Alerts, Profile and Services are the employee's
own records and notifications, not admin modules.

---

## 4. The two denial behaviours

Different questions get different answers, deliberately.

**A module the user cannot read → hidden.** The tile is not rendered at all. It would otherwise sit
there greyed out forever, and a field user cannot act on it anyway.

**An action the user cannot perform → visible but disabled.** The "Add farm" pill stays, gains a lock
glyph, greys out, and explains itself on tap:

> You do not have permission to create farms. Ask your HR admin to grant it.

Hiding it would make the app look like it simply lacks the feature, and would leave the user with no
way to learn it exists or to ask for it. `AppPillButton(enabled: false)` carries the visual state; the
tap still fires so the caller can explain rather than silently swallow.

`PartyFormScreen._submit()` and `MarketFormScreen._submit()` re-check the same permission before
writing — defence in depth against a stale navigation stack. An **edit** is not re-gated:
correcting an existing record is a different act from filing a new one.

---

## 5. How it composes with feature flags

The app already had a *different* axis: deployment-wide flags from
`GET {zkteco}/api/v1/mobile/app-config` (`sales.enabled`, `payment.enabled`, `vehicle.enabled`,
`geo.tracking.enabled`, `marketing.enabled`). Those are **not** per-user — they turn a module off for
everyone.

Both are required:

```
module reachable = featureFlagEnabled AND permissionGranted
action allowed   = module reachable AND createPermissionGranted
```

The composition lives in the four existing service wrappers, which are the single enforcement point
for ~30 call sites:

- `MarketingService.isMarketingEnabled()`
- `PaymentService.isPaymentEnabled()`
- `VehicleService.isVehicleEnabled()`
- `GeoTrackingService.isGeoFeatureEnabled()`

That placement is not cosmetic. `GeoTrackingService.ensureEnabledIfAllowed()` runs at bootstrap **and
on every resume**, so without the permission check inside `isGeoFeatureEnabled()`, a user who may not
see the Geo module would still have the app uploading their location in the background.

---

## 6. Comparison semantics

Deliberately aligned with the HRM web client
(`PeoplesHRM_FontEnd/src/services/AuthorizationService.js`) so the same grant means the same thing in
both apps.

| Rule | Behaviour | Why |
|---|---|---|
| Case | **Insensitive** — stored and compared lowercased | Matches `canRender`, which lowercases both sides. |
| Wildcards | **None** — exact match only | The web client has none either. |
| Empty *requirement* | Satisfied | `canRender([])` is a no-op; a tile with no `moduleKey` is ungated. |
| Empty *grant list* | **Denies** every gated module | Fail closed. A user with no permissions sees nothing gated. |
| Not yet fetched | **Denies** | Same, so a gated tile cannot flash into view and vanish. |
| `isAdmin` / `isSuperAdmin` | **Bypass everything** | Mirrors the web client. |

### The admin flag trap

`pphl_erp` sends `isAdmin` and `isSuperAdmin` as the **strings** `"1"` / `"0"`, and the web client
reads them with `Boolean(parseInt(v))`. `AuthUserProfile.parseAdminFlag` replicates that, so `"0"` is
falsy. Getting this backwards would hand **every employee** full access, which is why it has its own
test group.

---

## 7. Where the code lives

| File | Role |
|---|---|
| `lib/models/app_permissions.dart` | The catalogue and the module→permission maps. The only place a permission string is written. |
| `lib/services/permission_service.dart` | The engine. A `ChangeNotifier` singleton; `can` / `canAny` / `canAll`, admin bypass, `update()`, `clear()`. |
| `lib/models/auth_user_profile.dart` | Parses `permissions`, `roles`, `isAdmin`, `isSuperAdmin` from `get-my-info`. |
| `lib/screens/app_bootstrap.dart` | Feeds the service from the background profile fetch. |
| `lib/services/auth_service.dart` | Calls `clear()` on logout. |
| `lib/screens/employee_services_hub_screen.dart` | Filters the services-hub tiles. |
| `lib/screens/marketing/marketing_hub_screen.dart` | Filters tabs; locks the per-tab create pills. |
| `lib/widgets/ui/app_pill_button.dart` | The `enabled` state — greyed pill + lock glyph, still tappable. |

**Why a `ChangeNotifier` and not Provider/Riverpod/Bloc:** the app has no state-management dependency
at all. Adding one package for a single boolean set would have been the largest dependency change in
the repo. `ChangeNotifier` + `AnimatedBuilder` matches the existing `setState` idiom.

### A `TabController` trap worth knowing about

`MarketingHubScreen` filters its tabs, and a `TabController` cannot simply be rebuilt inside `build`:

- Creating one allocates an `AnimationController` via the state's mixin, so the swap must happen
  **outside** the build phase — hence `didChangeDependencies` plus a permission listener.
- Disposing the old controller immediately throws *"A TabController was used after being disposed"*
  because the outgoing `TabBar`/`TabBarView` still reference it. It is released in a **post-frame
  callback** instead.
- Two controllers are briefly alive, so the mixin had to change from `SingleTickerProviderStateMixin`
  to `TickerProviderStateMixin`, which asserts on more than one.
- `TabController(length: 0)` is a hard error, so an empty visible set keeps the existing controller and
  renders the "nothing to show" state.

`_syncTabController` carries the full explanation. `stage2_screen_build_test.dart` guards the pairing.

---

## 8. Security: what this is and is not

**This is a UX affordance, not a security boundary.** Hiding a tile does not stop anyone calling the API.

`pphl_erp` currently has **no permission enforcement at all**:

- `app/Http/Kernel.php:56-70` registers no `permission` / `role` middleware alias.
- `app/Providers/AuthServiceProvider.php:18-20` has an empty `$policies`, and its `Gate::before`
  callback calls `$user->hasRole(...)`, which `App\Models\User` does not define.
- No controller calls `$this->middleware(...)`; no `app/Policies/` directory exists.
- Consequently **any authenticated user** — including an ordinary employee — can call
  `GET /api/v1/get_permissions`, `POST /api/v1/add/role` and
  `POST /api/v1/role/permission/store`, and reassign role permissions.

### Open follow-up for the HRM backend team

1. Add a permission middleware (or Spatie middleware, given the package is already a dependency) and
   guard the role/permission admin routes listed above.
2. Decide whether the marketing endpoints on the ZKTeco app should also enforce `farms.read` /
   `markets.read` / `dealer.read` server-side.
3. Confirm the `farms.*` / `markets.*` / `vehicles.*` / `tracking.*` / `benefits.*` rows actually exist
   in the production `permissions` table, and how `vehicles.*` relates to the accounts client's
   `chicksVehicle.*`.

Until at least (1) lands, treat the permission list as a feature-flag source rather than a control.

---

## 9. Verification

| Check | Result |
|---|---|
| `flutter analyze` | 7 pre-existing `info`s, unchanged. **0 errors, 0 warnings.** |
| `flutter test` | **195 passing, 0 failing.** Baseline was 152 passing + 1 failing. |
| `test/app_permission_catalogue_test.dart` | 32 tests — parsing, admin-flag strings, fail-closed, case, `canAny`/`canAll`, module map, lifecycle. |
| `test/widget_test.dart` | 9 tests — hub tile visibility, admin bypass, and a tile appearing when permissions land after the first build. |
| `test/stage2_screen_build_test.dart` | +2 tests — a markets-only grant shows one tab; no grant shows the empty state. |

The suite's one **pre-existing failure** was `test/widget_test.dart`'s "App smoke test", which asserted
`find.text('AttendEase')` — a string that appears nowhere in the app (`main.dart` sets
`title: 'PPHL Attendance System'`) — and `find.text('Sign In')`, which only renders once
`AppBootstrap` resolves its network branch. It had been failing against a UI from a previous version.
Rather than delete the file, it was rewritten to assert the behaviour that now decides which tiles a
user sees.

### Not verified here

- **The live `user.permissions` payload.** The parser is defensive (tolerates a missing key, a lone
  string, a comma-separated string, `roles2` or `roles`, and `isAdmin` as string/bool/number), but the
  exact production shape was not checked against a live credential.
- **On-device behaviour.** Not run on an emulator or handset. Worth a manual pass: log in as a user
  with no marketing grants and confirm the Services hub hides Farms & dealers, Vehicles and Geo
  tracking while leaving Attendance, Leave and Payments visible.
