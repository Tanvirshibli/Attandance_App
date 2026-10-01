# Permissions Reference — Attandance_App

**Every permission the app currently enforces, and where each one is applied.**

Status: implemented. Last updated: October 2026.
Companion doc: [PERMISSION_ACCESS_CONTROL.md](./PERMISSION_ACCESS_CONTROL.md) — the design rationale,
the wire contract and the security caveats. This document is the *lookup table*: what exists, and what
it gates.

---

## 1. The short answer

An HRM admin assigns **permissions to a role**, a role to a user, and the app reads the user's
flattened permission list from `GET /api/v1/get-my-info` → `user.permissions`.

**Of the 25 permission strings the app knows, only 6 gate anything today.** The other 19 are carried
in the catalogue but have no screen to gate — the app has no payment-received, sales-order, live-bird,
fertilizer, chicks-booking or feed-booking module. They are ready, and start working the moment such
a screen is added and mapped in `AppPermissions`.

| # | Permission | Gates | Enforced at |
|---|---|---|---|
| 1 | `farms.read` | Farms & dealers hub tile; Farms tab | `employee_services_hub_screen.dart:29` · `marketing_hub_screen.dart:106` · `marketing_service.dart:41` |
| 2 | `markets.read` | Farms & dealers hub tile; Markets tab | same three sites |
| 3 | `dealer.read` | Farms & dealers hub tile; Dealers tab | same three sites |
| 4 | `farms.create` | "Add farm" pill; farm submit | `marketing_hub_screen.dart:334` · `party_form_screen.dart:497` |
| 5 | `markets.create` | "Add market" pill; market submit | `marketing_hub_screen.dart:334` · `market_form_screen.dart:444` |
| 6 | `dealer.create` | "Add dealer" pill; dealer submit | `marketing_hub_screen.dart:334` · `party_form_screen.dart:497` |
| 7 | `benefits.read` | HR benefits tile; Payments + HR benefits services | `employee_services_hub_screen.dart:29` · `payment_service.dart:47` |
| 8 | `vehicles.read` | Vehicles tile; vehicle service | `employee_services_hub_screen.dart:29` · `vehicle_service.dart:27` |
| 9 | `tracking.read` | Geo tracking tile; geo service | `employee_services_hub_screen.dart:29` · `geo_tracking_service.dart:116` |

That is **9 permissions covering 6 modules** (Farms, Dealers, Markets, Benefits, Vehicles, Tracking).

**Not gated at all:** Attendance, Leave, Payments tile, Sales info, and all five bottom-nav tabs.
These carry the employee's own records and notifications rather than admin-managed modules, so they
stay available to every signed-in user.

---

## 2. The full catalogue

All 25 strings live in one place: `lib/models/app_permissions.dart`. Nothing else in the app writes a
permission literal.

### Wired to a screen (9)

| Module | Strings |
|---|---|
| **Farms** | `farms.read` · `farms.create` |
| **Dealers** | `dealer.read` · `dealer.create` |
| **Markets** | `markets.read` · `markets.create` |
| **HR benefits** | `benefits.read` |
| **Vehicles** | `vehicles.read` |
| **Tracking** | `tracking.read` |

### Carried, not yet gating anything (16)

| Module | Strings | Why nothing gates them |
|---|---|---|
| Payment receive info | `prInfo.create` · `prInfo.read` | No payment-received screen in this app. |
| Sales orders | `salesOrder.create` · `salesOrder.read` | No sales-order screen. |
| Live bird orders | `liveBirdOrder.create` · `.read` · `.all` · `.live` · `.cull` | No live-bird screen. |
| Fertilizer orders | `fertilizerOrder.create` · `fertilizerOrder.read` | No fertilizer screen. |
| Chicks bookings | `chicksBooking.create` · `chicksBooking.read` | No chicks-booking screen. |
| Feed bookings | `feedBooking.create` · `feedBooking.read` | No feed-booking screen. |

⚠️ **These 16 need confirming before an admin can grant them.** `pphl_erp`'s own seeder
(`RolePermissionSeeder.php:29-71`) creates a completely different catalogue — `dashboard.*`,
`category.*`, `seller.*`, `user.*`, `role.*` — with **zero overlap**. And the list originally handed to
us was a partial excerpt of the *accounts* client's `pphl-accounts-client/src/constant/permissions.js`,
whose vehicle module is `chicksVehicle.*`, not `vehicles.*`.

Check with `GET /api/v1/get_permissions` against production before relying on any string.

---

## 3. Where each permission is enforced

### The engine

`lib/services/permission_service.dart` — `PermissionService.instance`, a `ChangeNotifier` singleton.

| Member | Purpose |
|---|---|
| `update(profile)` | Adopts the permissions from a `get-my-info` result. Called once, in the background. |
| `clear()` | Drops all state on logout. |
| `can(permission)` | Single permission, case-insensitive, admin bypasses. |
| `canAny(list)` | Any-of — used for a module with several valid reads. |
| `canAll(list)` | All-of — for an action needing several grants. |
| `canViewModule(key)` | Module visibility. |
| `canCreateIn(key)` | Create-action permission. |
| `denialMessage(key)` | The user-facing "you do not have permission to…" text. |

**Lifetime:**

| Moment | Call | Why there |
|---|---|---|
| Cold start | `app_bootstrap.dart:126` — `update(profile)` inside `_warmAuthenticatedSession()` | The profile fetch already runs unawaited so the first frame is never blocked. Permissions cost **no extra request and no latency**; tiles appear when it lands. |
| Logout | `auth_service.dart:535` — `clear()` | A shared device must not show the previous user's modules to the next person. |

### Services — the enforcement backstop

Each of these composes the permission with an existing deployment-wide feature flag and is the single
place ~30 call sites check. **This is the layer that fails closed** if a gated screen is reached by a
stale navigation stack or a future deep link.

| Service method | File:line | Checks |
|---|---|---|
| `MarketingService.isMarketingEnabled()` | `marketing_service.dart:41` | `marketing.enabled` **AND** any of the 3 marketing reads |
| `PaymentService.isPaymentEnabled()` | `payment_service.dart:47` | `payment.enabled` **AND** `benefits.read` |
| `VehicleService.isVehicleEnabled()` | `vehicle_service.dart:27` | `vehicle.enabled` **AND** `vehicles.read` |
| `GeoTrackingService.isGeoFeatureEnabled()` | `geo_tracking_service.dart:116` | `geo.tracking.enabled` **AND** `tracking.read` |

`GeoTrackingService` is the one that most needs to be right: `ensureEnabledIfAllowed()` runs at
bootstrap **and on every resume**, so without the permission check there, a user who may not see the
Geo module would still have the app uploading their location in the background.

### Screens — what the user sees

| Surface | File:line | Behaviour when denied |
|---|---|---|
| Services hub tiles | `employee_services_hub_screen.dart:29` (`_visibleTiles`) | Tile **hidden** |
| Marketing hub tabs | `marketing_hub_screen.dart:106` (`_visibleTabs`) | Tab **hidden**; controller resized to match |
| Marketing create pill | `marketing_hub_screen.dart:334` | Pill **visible but disabled** — greyed, lock glyph, tap explains |
| Farm / dealer submit | `party_form_screen.dart:497` | Submit **blocked** with the reason |
| Market submit | `market_form_screen.dart:444` | Submit **blocked** (an *edit* is not re-gated) |

---

## 4. The two denial behaviours

Different questions, different answers — deliberately.

**Cannot read a module → hidden.** The tile is not rendered. A field user cannot act on it anyway,
and a permanently greyed tile is noise.

**Cannot perform an action → visible and disabled.** The pill stays, gains a lock glyph, and on tap
says:

> You do not have permission to create farms. Ask your HR admin to grant it.

Hiding it would make the app look like it simply lacks the feature, and would leave the user with no
way to learn it exists or to ask for it.

Implemented in `lib/widgets/ui/app_pill_button.dart` via the `enabled` flag — greyed foreground,
`Icons.lock_outline` in place of the action's own icon, and **still tappable** so the caller can
explain rather than silently swallow.

---

## 5. Comparison semantics

Aligned with the HRM web client (`PeoplesHRM_FontEnd/src/services/AuthorizationService.js`) so the
same grant means the same thing in both apps.

| Rule | Behaviour | Why |
|---|---|---|
| Case | **Insensitive** | Matches `canRender`, which lowercases both sides. |
| Wildcards | **None** — exact match | The web client has none either. |
| Empty *requirement* | Satisfied | A tile with no `moduleKey` is ungated by design. |
| Empty *grant list* | **Denies** every gated module | Fail closed. |
| Not yet fetched | **Denies** | Same, so a tile cannot flash into view and vanish. |
| `isAdmin` / `isSuperAdmin` | **Bypass everything** | Mirrors the web client. |

### Super admin sees everything — always

`isAdmin` or `isSuperAdmin` set to `"1"` grants **every module and every action**,
whether or not any permission string is present. A super admin whose role carries
all the individual permissions *disabled* still gets full access.

This is asserted leaf-by-leaf: the test walks
`AppPermissions.moduleReadPermissions`, `moduleCreatePermissions` and
`AppPermissions.all` and checks each one, so a module added later is covered
automatically rather than silently going untested.

`test/manual_login_permissions_test.dart` →
*"a super admin sees every tile on the very first fetch"*.

### The admin-flag trap

`pphl_erp` sends `isAdmin` and `isSuperAdmin` as the **strings** `"1"` / `"0"`, and the web client
reads them `Boolean(parseInt(v))`. `AuthUserProfile.parseAdminFlag` replicates that, so `"0"` is
falsy. **Getting this backwards hands every employee full access**, which is why it has its own test
group.

---

## 6. Adding a permission later

1. Add the string to `AppPermissions` (`lib/models/app_permissions.dart`) and to `AppPermissions.all`.
2. Add it to `moduleReadPermissions` (and/or `moduleCreatePermissions`) — **that map is the single
   source of truth for the module→permission binding.**
3. Give the screen's tile a `moduleKey` in `employee_services_hub_screen.dart`, or its tab a key in
   `_tabs` (`marketing_hub_screen.dart:64`).
4. Add the service-level check if the module has a service wrapper.
5. Add a case to `AppPermissions.subjectFor` so the denial message names the right action.

**Never write a permission literal at a call site.** Unknown strings are ignored by design — that is
what keeps an HRM catalogue change from crashing an installed build — which also means a typo at a
call site fails *open*, not loud.

---

## 7. What this is not

**A UX affordance, not a security boundary.** Hiding a tile does not stop anyone calling the API.

`pphl_erp` currently has **no permission enforcement at all**:

- `app/Http/Kernel.php:56-70` registers no `permission` / `role` middleware alias.
- `app/Providers/AuthServiceProvider.php:18-20` has an empty `$policies`; its `Gate::before` calls
  `$user->hasRole(...)`, which `App\Models\User` does not define.
- No controller calls `$this->middleware(...)`; there is no `app/Policies/` directory.
- So **any authenticated user** — including an ordinary employee — can call
  `GET /api/v1/get_permissions`, `POST /api/v1/add/role` and
  `POST /api/v1/role/permission/store`, and reassign role permissions.

Tracked as a backend follow-up in [PERMISSION_ACCESS_CONTROL.md §8](./PERMISSION_ACCESS_CONTROL.md).

---

## 8. Verification

| Test | Covers |
|---|---|
| `test/app_permission_catalogue_test.dart` (32) | Profile parsing, admin-flag strings, fail-closed, case-insensitivity, `canAny`/`canAll`, the module map, `clear()` / listener behaviour, and that all 25 catalogue strings are unique and well-formed. |
| `test/manual_login_permissions_test.dart` (7) | Drives the **real** `AuthService.getCurrentUserProfile()` with a stubbed response. Proves permissions reach the service on a *manual* sign-in, that a super admin sees **every** module and every grant on the first fetch, that an empty list still denies, and that a second user's grants replace the first's. **All 7 fail if the `update()` call is removed** — that was the reported bug. |
| `test/widget_test.dart` (9) | Hub tile visibility with no grants, with grants, and for an admin; a tile appearing when permissions land after the first build. |
| `test/stage2_screen_build_test.dart` (+2) | A markets-only grant shows one tab, not three; no grants shows the empty state. |

Suite: **237 passing, 0 failing** at the time of writing.
