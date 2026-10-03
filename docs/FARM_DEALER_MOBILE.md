# Farm & Dealer Mobile Module

Last updated: September 30, 2026 — **v2.5.0+97**

Field data collection for **markets**, **dealers**, and **farms** in Attandance_App, backed by ZKTeco `/api/v1/mobile/marketing/*` (no JWT — same pattern as geo). Employee identity uses profile `canonicalEmployeeId` (`employees.id`).

**v2.5.4: The Add Farm screen is a lookup, not a form.**
Tapping the search field now lists every farm in the officer's zones and typing narrows that list — no network round-trip per keystroke. The form itself (details, products, photos) stays hidden until **Add new farm** is chosen, and choosing it closes the list. Farm name and phone moved after the farm code, and the separate trade name field is gone: the farm name is written to both columns. See [Add Farm screen](#add-farm-screen).

**v2.5.3: Add Farm is its own screen, and it starts with a duplicate check.**
`FarmFormScreen` (`lib/screens/marketing/farm_form_screen.dart`) replaces the farm branch of `PartyFormScreen`, so farm, dealer and market layouts are independent from here on. The screen opens on a searchable **existing-farm lookup** — a hit offers a visit report instead of a second record; a miss offers **Add new farm**. The form itself is re-ordered, several fields are gone, and `visit_type` / `capacity_limit` are new columns on `mkt_parties`. See [Add Farm screen](#add-farm-screen).

**v2.5.2+99: Manual company → sector → market selection.**
The org master is retired. Zone stays read-only, but company, sector and market are the officer's own picks and cascade downwards; the zone no longer narrows any of them, nor the ERP dealer picker. See [Organisational selection](#organisational-selection).

**v2.5.0+97: Relational org master, required farm phone, live dealer picker.**
Company and sector no longer render "Unresolved from your profile". The relation now lives in the ZKTeco backend as a real org master (`mkt_zones` / `mkt_companies` / `mkt_sectors` / `mkt_zone_sectors`), synced from Sales by `marketing:sync-masters`, and the app asks one endpoint instead of guessing. A farm's phone number is now **required and unique among farms** — the old "farms are exempt" rule is gone. The ERP dealer field is removed from the farm form and the existing-dealer picker is now a live Sales-backed list, shown only for an existing dealer, which autofills what the ERP record actually holds. See [Phone uniqueness](#phone-uniqueness), [Existing dealer picker](#existing-dealer-picker).

**v2.4.0+94: Full-screen grids, employee-scoped read-only fields, generated codes.**
The hub's three module cards are replaced by one full-height grid per tab with a pinned action bar. Dealer / farm / market codes are allocated server-side (`DLR-09260001`). See [Hub layout](#hub-layout), [Organisational selection](#organisational-selection), [Record codes](#record-codes).

**v2.3.0+93: Tabbed hub + labelled pill actions.** The hub is three **tabs** (Farms / Dealers / Markets) instead of three stacked cards, and the icon-only Create / View-all buttons are **icon + text pills**. Party detail's "Post a visit" and "New follow-up" are pills too. See [Hub layout](#hub-layout).

**v2.3.0+92: Zone scoping.** Every marketing list, form picker and dealer dropdown is now narrowed to the zones the employee is assigned. See [Zone scoping](#zone-scoping) below.

**v2.3.0+85:** Market rework — "Market visit" removed; markets are now **market surveys** (create once, **Edit** on the detail screen → `PUT /markets/{id}`). Market survey fields: `feed_share_percent`, `chicks_share_percent`, `product_types[]`, `feed_dealer_count`, `chicks_dealer_count`, `broiler_farm_count`, `layer_farm_count`, `color_farm_count`, `cock_farm_count`, `competitor_companies[]` (`name` + `share_percent`). **Zone hierarchy** (`company > zone > sector`): profile `zoneId`/`zoneName` filters all marketing lists (`zone_id` param); dealer create requires a zone; visits store `zone_id`/`zone_name` (party zone fallback server-side). Dealer visit: autofills market/company/sector from the party, **photo required**, new `feed_findings` + `chicks_findings`, feed unit catalog includes **Ton**. All uploads compress client-side to **WebP** (`flutter_image_compress`) and post under the **`image`/`image[]`** parent field (legacy `photos[]` still accepted server-side). Payment-receive posts accept an optional receipt photo per line (`payments[i][image]` file field nested inside `payments[i]` — lines without a photo are omitted; the earlier top-level `image[i]` fields are ignored by the current API). The Payments list shows returned receipt thumbnails (tap to zoom). Every manual-typing text field has a voice mic (`speech_to_text`, English/Bangla picker).

**v2.2.3+78:** Farm visit report flock metrics reordered (present mortality before total; avg feed before read-only total feed kg; total body weight before Production% / FCR). Hatch date defaults today; per bag weight defaults **50** kg. Total feed intake auto-calculates `quantity × avg_feed_intake_g / 1000` (read-only). Mortality % and rest of bird stay auto-computed from quantity + total mortality. Dealer visit product rows: amount = order qty × unit price (read-only). Market visit rows: quantity above price; amount = quantity × price (read-only, included in payload).

**v2.2.3+77:** Hub and party master lists are company-wide (`employee_id` omitted on `GET /parties`). Any employee sees farms/dealers created by others; visits/surveys/follow-ups stay employee-scoped.

**v2.2.3+70:** Marketing attachment URLs served correctly (ZKTeco `web` mounts `zkteco-storage` + `storage:link`). Farm / dealer / market visit photos upload and show on detail screens (`GET /farm-surveys/{id}`, new `GET /visits/{id}`). Dealer and market visit forms redesigned as paper-style sections (identity → visit → commercial/intel → narrative → products → photos). Products prefer Sales `form-data`; units stay demo. Searchable fields: tap outside or suffix arrow to collapse suggestions.

**v2.2.3+68:** Farm visit report detail shows uploaded photo thumbnails (tap to zoom). Form uses one **Production% / FCR** field (e.g. `85% / 1.87` or `1.87`); parsed into API columns with raw value in `extra_data.production_fcr_note`.

**v2.2.3+66:** Three separate visit forms — **Farm visit report** (`POST /farm-surveys`, farm party only), **Dealer visit** (`POST /visits`, dealer party), **Market visit** (`POST /visits`, market fixed + party picker). Farm report: dealer block read-only from parent party; breed/DOC/etc. use type-to-search autocomplete (`SearchableTextField`). Dealer/market visits no longer offer `survey` type.

**v2.2.3+64:** Markets hub panel uses purple (`AppColors.secondary`) so it is visually distinct from Dealers (blue primary). Previous builds used `AppColors.info`, which matched primary at low tint.

**v2.2.3+63:** Hub sections use distinct tinted panels (Farms green, Dealers primary blue, Markets purple). Farm visit report accepts **free-text** breed, DOC/feed company, shed, curtain, floor, territory, and zone with demo suggestion chips (CB, Provita, PPHL, Open shed, Cloth, Concrete house, zones A/B/C, etc.). Labels clarify units (avg feed g/bird, avg B/W grams, space sq ft). Editable farming years; visit type and temperature range stored in `extra_data`. Home Recent Attendance badge no longer overlaps check-in/out times.

**v2.2.3+61:** Renamed to **Farms, Dealers and Markets**. Hub sections (Farms → Dealers → Markets) show top **5** preview rows; compact **Create** (+) and **View all** (list) icon buttons sit on the title row. Tap a preview row for the record page; pull-to-refresh reloads previews.

**v2.2.3+60:** Farm & Dealer hub uses expandable **Create** / **View all** cards (no FABs, no standalone Visits tile). Farm records open the paper **Farm visit report** (rewritten farm survey). Dealer records still use the stock/order visit form. Posting a visit lives on the farm or dealer record page.

**v2.2.3+59:** Create forms collect the full Phase-1 field set the current marketing API already accepts. ID fields are type-to-search (`SearchableSelectField`). Live lists are used for markets, parties, and visits (FK-checked). Demo catalog fills ERP-style IDs (dealers, products, units, employees) until live master APIs exist. Company / sector prefer Sales `GET /api/booking-person-books/form-data` (Bearer); demo companies/sectors fill the picker when that list is empty.

Create forms auto-capture GPS + reverse-geocode address fields (no manual Capture GPS buttons). Attachments stay **photos only**: picked images are compressed to **WebP client-side** (`ImageUploadService`) and posted under the **`image[]`** field (legacy `photos[]` still accepted by ZKTeco). Documents, signature, audio, and video wait for a later API.

---

## Entry point

Services tab → **Farms, Dealers and Markets** → `MarketingHubScreen`

The hub is a **three-tab page**: Farms, Dealers, Markets. Farms is selected on open. Each tab holds one module card with up to **5** recent preview rows (tap → record detail). **Follow-ups** is a tile below the tabs, reachable from all three. **View all** opens the full list screen.

| Tab | Create | View all | Preview tap |
|-----|--------|----------|-------------|
| Farms | `FarmFormScreen` | `PartyListScreen(farm)` | `PartyDetailScreen` → Post visit report |
| Dealers | `PartyFormScreen(dealer)` | `PartyListScreen(dealer)` | `PartyDetailScreen` → Post visit |
| Markets | `MarketFormScreen` | `MarketListScreen` | `MarketDetailScreen` → Post visit |
| *(below the tabs)* Follow-ups | — | `FollowupFormScreen` (list mode) | — |

| Visit entry | Screen | API |
|-------------|--------|-----|
| Farm party → Post a visit | `FarmSurveyFormScreen` | `POST /farm-surveys` |
| Dealer party → Post a visit | `DealerVisitFormScreen` | `POST /visits` |
| Market detail → Post a visit | `MarketVisitFormScreen` (pick party in market) | `POST /visits` |

---

## Add Farm screen

**v2.5.3.** `lib/screens/marketing/farm_form_screen.dart` — `FarmFormScreen`.

### Why it is a separate file

`PartyFormScreen` used to render **both** farm and dealer, split by a single `_isFarm` boolean, so every field change on the farm side moved a control on the dealer side and vice versa. Farm collection has its own field set and its own order now, so it gets its own widget class, its own `_FarmProductRow`, and its own state.

The dealer form (`PartyFormScreen`, `initialPartyType: 'dealer'`) and the market form (`MarketFormScreen`) are **untouched**. Only the leaf widgets are shared — `SearchableSelectField`, `ReadOnlyField`, `VoiceTextField`, the `AppCard` / `AppHeader` kit, and the marketing services. The parent form's layout code is not reused, which is the point.

### Search first

**v2.5.4.** The screen opens as a **lookup**, not a blank form. A farm is found by name and identified by its phone, so both are searched at once.

| State | Shown |
|---|---|
| Untouched | Just the search field |
| Field tapped | Every farm in the officer's zones, scrollable, with **Add new farm** in the list header |
| Typed | The same list, narrowed |
| A farm tapped | Name, code, phone, zone + **Post a visit report** / **Cancel** |
| Nothing matches | *"No farm found"* + **Add new farm** |
| Load failed | *"Could not load existing farms"* + **Add new farm** |

**The list is fetched once per screen, not per keystroke.** `MarketingService.listFarms()` pulls the zone-scoped set on first focus and `FarmFormScreen.filterFarms` narrows it locally. Re-querying would put a network round-trip between every character on a list the device already holds.

> **A failed load is not an empty list.** Offering to create a farm off a network blip is how a duplicate gets filed, so the failure keeps its own wording. The create path stays open — the server's own uniqueness rule is the authority — but the screen says it could not check.

**Post a visit report** pushes `FarmSurveyFormScreen(party: match)` — the same call the farm detail screen makes. No second record is created.

**Add new farm** reveals the form and seeds one field from the query: a digit run of 7+ characters (`FarmFormScreen.minPhoneDigits`) cannot be a farm name, so it goes to **Phone**; anything else goes to **Farm name**. The other field is left blank rather than guessed.

**Choosing "Add new farm" also closes the list** and unfocuses the field. The farm list was the way *into* that decision; keeping it open would push the form the officer now has to fill in below a scrollable panel they no longer need. The typed query stays in the field, which turns **read-only** and relabels to *"Searched for"* — it is now a record of what they looked for, not something to edit. The clear button is disabled at that point too, because `_resetSearch` discards the whole form rather than just the query.

Narrowing compares **digits first** for a phone-shaped query, so typing a farm's exact number surfaces that farm rather than burying it among farms whose phone merely contains those digits as a substring. Name, code and phone all match, case-insensitively. Under two characters everything is offered — a one-letter query matches most of the catalogue, and a list that looks broken is worse than a long one.

### Everything else waits for "Add new farm"

**v2.5.4.** The farm details, the product rows and the photo gallery all render only after the officer commits. Previously the product table and photo picker were rendered unconditionally, so the screen opened with a search bar above an empty product grid — an officer who had just found the farm they meant was looking at controls they were about to discard.

The first product row is seeded in `_startCreating()` rather than `initState`, for the same reason: a row built before the section is visible is a set of controllers nobody can type into. Going back to search-only (`Cancel` / the clear button) drops the rows, so the next "Add new farm" does not inherit the previous attempt's products.

### Field order

| # | Field | Notes |
|---|-------|-------|
| 1 | **Search existing farm** | tap to browse the zone, type to narrow |
| 2 | **Visit type** | `regular_farm` (default) / `model_farm` / `other_farm` |
| 3 | **Zone** | read-only, from the HRM profile |
| 4 | **Parent dealer** | live `mkt_parties` dealer list, searchable |
| 5 | **Farm code** | read-only, server-allocated `FMR-…` |
| 6 | **Farm name** `*` | seeded by the search; also written as the trade name |
| 7 | **Phone** `*` | seeded by the search; live uniqueness check |
| 8 | **Company** | **Peoples Poultry & Hatchery preselected** |
| 9 | Owner name | |
| 10 | **Farm type** | `broiler` / `layer` / `color` / `all` |
| 11 | **Capacity** + **Capacity limit** | one row, two number fields |
| 12 | Capacity unit | |
| 13 | Email / NID / Trade license | |
| 14 | Address | auto-filled from reverse geocode |
| 15 | Notes | |

**v2.5.4:** farm name and phone moved **after** the farm code. The code is the record's identity and is already settled, so what follows is what the officer actually supplies.

**Removed:** party type (now fixed in the payload, never rendered), sector, market, contact person, alt phone, business years, credit limit, payment mode, lead status, and — in v2.5.4 — **trade name**.

### One name, two columns

**v2.5.4.** There is no separate trade name field. `FarmFormScreen.tradeNameFor` writes the farm name to **both** `name` and `trade_name`, because the two are read by different consumers:

| Column | Read by |
|---|---|
| `name` | the web farms report (`MarketingFarmsReportPage` export) |
| `trade_name` | `Party.displayName`, which prefers `tradeName` over `name` |

Filling only one leaves the farm blank in the other place. The value is trimmed, and `null` when blank so the column stays `NULL` rather than holding `''`.

With sector and market gone there is no cascade on this screen, so the company picker is a flat list and `MarketingMasterService.filterSectorsForCompany` / `filterMarketsForSector` are used only by the dealer and market forms.

### Product rows

| Order | Field | Change |
|---|---|---|
| 1 | **Product category** | renamed from *Category*, moved to the top |
| 2 | **Product** | moved directly below the category |
| 3–8 | Product name, relation type, unit, product company, brand name, monthly / demand | unchanged |
| 9 | Our product | switch, unchanged |
| 10 | Product notes | unchanged |

**Removed:** Stock, unit price, competitor company.

Choosing a category filters the product list beneath it. A product already picked from another category is dropped when the category changes, because the two would otherwise contradict each other on submit. Changing the category does not re-add the product — it was a different product, not a stale one.

> The category and product pickers still read `MarketingDemoMasters`, not the live Sales catalogue. That is unchanged from v2.5.x and was left alone here.

### Default company

`FarmFormScreen.defaultCompany` matches a lowercased substring `peoples poultry` on `displayName`, so *"Peoples Poultry & Hatchery Ltd"* and *"Peoples Poultry and Hatchery Ltd"* both hit. It falls back to the first company when nothing matches, and to `null` on an empty list — submit blocks with *"Choose the company this farm belongs to."* An id is never invented.

### Payload changes

**Added:** `visit_type`, `capacity_limit`.

**`trade_name` is no longer a separate input** — it is written from the farm name (see [One name, two columns](#one-name-two-columns)), so the key is always present rather than conditional.

**Removed** (all nullable server-side, so omitting them is safe): `sector_id`, `sector_name`, `market_id`, `contact_person`, `alt_phone`, `business_years`, `credit_limit`, `payment_mode`, `lead_status`. Product rows drop `current_stock`, `stock_qty`, `unit_price`, `competitor_company`.

`party_type: 'farm'` still rides in the payload; it is simply never shown.

### Backend

Two new nullable columns on `mkt_parties`, from `2026_10_03_100000_add_visit_type_and_capacity_limit_to_mkt_parties`:

| Column | Type | Notes |
|---|---|---|
| `visit_type` | `string(30)`, indexed | `in:regular_farm,model_farm,other_farm` |
| `capacity_limit` | `decimal(18,4)` | |

Both are strings/doubles rather than a database enum, so a fourth visit kind is a code change rather than an `ALTER TYPE` on a live table — the same reasoning `party_type` already follows. Declared and validated at the same width, deliberately avoiding the `farm_type` mismatch where the column is `string(30)` but the rule is `max:80`.

`visit_type` here is a property of the **farm**, not of a visit. `mkt_visits.visit_type` is a separate column recording what a visit was, and is untouched.

---

## Organisational selection

**v2.5.2+99.** The dealer, farm and market forms show the logged-in officer's **zone read-only**, and let the officer pick their own **company**, then **sector**, then **market**. The zone does not narrow any of them.

### Why

Company and sector used to be derived from the employee's HRM profile. That could not work: `pphl_erp`'s `get-my-info` exposes a single free-text `sector` **name** and **no company at all**, and that name is frequently the literal `'N/A'`. The backend org master was then built to bridge the gap, resolving zone → sector → company through a synced table set.

That whole mechanism is now retired. Mirroring zones, companies and sectors from another application to answer a question this app could ask the master directly was the wrong shape: it needed a scheduler, four tables, a resolver, an admin sync button, and it still could not fill in a company for a zone with no sector link.

### What the forms do now

| Field | Source | Behaviour |
|---|---|---|
| Zone | HRM profile `zoneId` → Sales `get-zone` | Read-only. A fact about who is filing the record. |
| Company | Sales `form-data` company list | **Required.** The officer picks it. |
| Sector | Sales `form-data` sectors, filtered by the chosen company's `companyId` | Optional on a party, required on a market. |
| Market | `mkt_markets`, filtered by the chosen sector's `sectorId` | Optional. |

Each picker clears everything below it: changing the company drops the sector and market, because a sector from the previous company would file the record under a pairing that cannot exist.

The sector list follows the **real** `companyId` edge Sales ships on every sector row (`BookingPersonWiseBookingsService::getChicksSectorList`, `getFeedSalesPointList`). The app never guesses a company from a name — that was the old bug.

`MarketingMasterService` (`lib/services/marketing_master_service.dart`) holds the company, sector and market lists, cached for 24 h. `filterSectorsForCompany` and `filterMarketsForSector` are static and pure so the cascade is unit-tested without a network round-trip.

### Why the zone stopped filtering

Narrowing the pickers by zone hid options an officer legitimately needed. A dealer who trades across a neighbouring zone could not file it; a sector belonging to the officer's company but a different territory was invisible. Zone remains read-only and still files with the record, because every marketing list and report keys off it.

### The existing ERP dealer picker is unfiltered

`GET /marketing/dealers` returns the whole Sales dealer master. A Sales dealer row is `tradeName`, `dealerCode`, `contactPerson`, `phone`, `alterPhone`, `address` and a zone — **there is no company or sector edge on it**, and `pphl_account-laravel`'s `dealers` table has no `company_id` column. Narrowing the picker by company is therefore not implementable without changing that application. It is offered searchable instead.

### Names travel with the ids

The app posts `company_name` and `sector_name` alongside the ids. The webapp reports read the names straight off the row — it has no org master to resolve a name from, and `zone_name` was already stored this way.

> **Still never guessed.** Every id sent is one the officer picked from a real master list. A wrong `company_id` files a dealer under another company, a silent data error an admin has to find and undo.

### Graceful degradation

| Condition | Result |
|---|---|
| Zone resolves | Shown read-only, filed with the record |
| Zone does not resolve | *"Not set — ask an admin to set your zone"*, and submit is blocked |
| Company not picked | Submit blocked with a clear message |
| Sector / market not picked | Key omitted from the payload |
| Org master unreachable | Empty picker rather than a hung form |

### Rendering

`ReadOnlyField` (`lib/widgets/ui/read_only_field.dart`) still renders the **Zone**, the server-allocated **Code**, and a farm's **Party type**: a sunk `AppColors.surfaceSunk` box, `AppColors.inkFaint` text, **no mic**, **no tap handler**, and a small `Icons.lock_outline` suffix. A `SearchableSelectField` with `enabled: false` would still render as something tappable; this renders as a settled fact.

Company, sector and market are `SearchableSelectField`s. Sector stays disabled with the hint *"Pick a company first"* until a company is chosen, and market stays disabled with *"Pick a sector first"* until a sector is — so the cascade is visible before the officer touches anything.

The farm visit report's **Zone** is read-only on the same terms, with one difference: **the farm's own zone wins** when it has one (the report is about that farm, not the officer), falling back to the officer's zone for a farm created before zone tagging.

---

## Record codes

**v2.4.0+94.** Codes are `{PREFIX}-{MM}{YY}{SEQ}`, e.g. `DLR-09260007`. The sequence restarts each month.

| Record | Prefix | Source |
|---|---|---|
| New dealer / existing dealer | `DLR` | `GET /marketing/parties/next-code?prefix=DLR` |
| Farm | `FMR` | `GET /marketing/parties/next-code?prefix=FMR` |
| Market | `MRK` | `GET /marketing/markets/next-code?prefix=MRK` |

- **Allocated server-side under a row lock** (`mkt_marketing_code_sequences`, keyed by prefix + period). A client-side "highest existing + 1" collides the moment two officers open a form in the same second, and that is exactly what the endpoint exists to prevent.
- **`prefix` is a whitelist**, not free text, so the endpoint cannot be used to allocate arbitrary codes.
- **Failure leaves the field empty** ("Unavailable — will save without one") rather than inventing a number on the device. `code` is nullable server-side; a missing code is far better than a duplicate.
- **Markets keep their existing code on edit.** A saved market's `_effectiveCode` prefers `widget.market.code`, so a correction never renumbers a record people already reference.

---

## Phone uniqueness

**v2.5.0+97.** A party is identified by its phone number, so one number belongs to one record. Required for **every** party the forms create, farm included.

| Field | Required | Unique |
|---|---|---|
| Dealer / existing dealer | yes | yes, among dealers |
| Farm | **yes** (changed) | **yes, among farms** (changed) |
| Market | yes | yes, unconditionally |

### Uniqueness is scoped to a pool

This reverses the v2.4.0 rule, which said *"Farms share `mkt_parties` with dealers but are not looked up by phone, so they do not inherit the requirement."* That reasoning no longer holds: the farm form has to make a farm findable by the same number an officer would dial.

The change that makes it safe is that uniqueness is **pool-scoped**, not global:

```
farm pool    party_type IN ('farm','farmer')
dealer pool  party_type IN ('dealer','outlet')
```

A farm and a dealer may legitimately share a number — one person can run a farm and trade as a dealer — while two farms may not. The single global index from `2026_09_30_100000` is replaced by `mkt_parties_farm_phone_uniq` and `mkt_parties_dealer_phone_uniq` in `2026_10_01_110000`. `prospect` sits in neither pool: it stays valid in the enum and in existing rows, but the forms never create one.

> **Why partial.** Both pools filter `WHERE phone IS NOT NULL AND deleted_at IS NULL` — the model uses `SoftDeletes`, and a deleted party must not hold their number hostage forever. Where a pool already holds duplicates the DDL is skipped rather than failing the deploy; the API-level rule still keeps new rows correct.

Three layers, because the client cannot be the authority:

1. **Debounced client check.** `GET /parties?q=<digits>` on a 700 ms debounce while typing, and again on submit (the debounce can lag an edit). The backend `q` filter is a substring `LIKE`, so **every hit is compared after normalisation** — comparing raw strings would let `01712-345678`, `+8801712345678` and `01712345678` register as three different dealers.
2. **`MarketingService.normalisePhone` / `samePhone`.** Strips spaces, dashes and parentheses, drops a `+88` / `0088` country code, then a national leading `0`. An empty or missing phone never matches anything.
3. **Server normalisation + `unique` rule + partial unique index.** The client's early warning is a convenience; the 422 is the enforcement. A clash shows as *"Already linked to <name> (<code>)"* rather than a raw validation blob.

> **The client warning is pool-aware too.** `_checkPhone` skips a same-number hit in the *other* pool. Warning about a farm/dealer number share would block a save the database happily accepts, which is the same class of bug as the unresolved-id rule below.

> **The server normalises on write too.** A unique index compares raw strings, so `MktParty` / `MktMarket` store the canonical national form (`+8801712345678` is stored as `01712345678`) and both controllers rewrite the input *before* validating. Without that last part a `+880` duplicate would pass validation and then trip the DB index as a 500. The stored form keeps its trunk `0` — it is displayed verbatim on the detail screens.

> **Partial updates read the stored type.** A `PUT` carrying only `phone` has no `party_type` in the body, so the controller falls back to the row's stored type for pool membership. Without that, editing a dealer's phone would be validated against the farm pool and could be rejected for a clash the real index would never raise.

**A failed lookup is not a pass.** It only means the early warning is unavailable — the submit still goes out and is still validated by the server.

---

## Existing dealer picker

**v2.5.0+97.** The dealer's **party type** dropdown offers two options: **New dealer** → `dealer`, **Existing dealer** → `outlet`. Both were already in the API enum, so no backend change was needed to name them.

The **Existing ERP dealer** field is a separate thing and has changed twice:

| | Before | After (v2.5.0+97) |
|---|---|---|
| Farm form | always visible | **removed** — a farm has no ERP dealer, and the visible field only invited filing a farm against a demo row |
| Dealer form | always visible | **only when party type is Existing dealer** |
| Source | `MarketingDemoMasters.dealers` — 3 hardcoded rows | live Sales master via `GET /marketing/dealers` |

The demo rows carried only an `id` and a `name`, so selecting one could never autofill anything. The live list carries a real `contactPerson`, `phone`, `alterPhone`, `address` and `zoneName`, and selecting one fills **only the fields it actually has a value for** — a dealer with no address does not blank an address the officer already typed.

- The picker's selection is written as `existing_dealer_id`, which is a **Sales** id, not an `mkt_parties` id. It is kept for traceability only.
- The list is fetched lazily, on first render as an existing dealer and again when the party type is switched to it. A new dealer or a farm never issues the request.
- **Unfiltered** as of v2.5.2+99 — see [Organisational selection](#organisational-selection). The Sales dealer master carries no company or sector edge, so the picker cannot be narrowed by either, and narrowing by the employee's zone would hide dealers they legitimately trade with. It is offered searchable by name, code, contact person or phone instead.

---

## Hub layout

### Full-screen grids (v2.4.0+94)

The page no longer scrolls. `Scaffold.body` is a plain `Column`, not a `CustomScrollView`:

```
Column
├── AppHeader
├── _ZoneScopeNote              (unchanged, when the scope is non-empty)
├── TabBar                      (unchanged)
├── Expanded
│   └── TabBarView              ← every remaining pixel
│       └── per tab: _RecordGrid (GridView.builder, scrolls on its own)
└── bottomNavigationBar: _HubActionBar  ← Add … / All … / Follow-ups, pinned
```

- The `_HubGroupCard`, the five-row preview lists and the fixed `268 dp` tab body are all gone. They existed only to fit three stacked cards on one screen, and the five-row cap was why "View all" was a mandatory second tap for anything longer.
- **Delegate**: `SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 0.78, spacing: AppSpace.sm)`. Max-cross-axis rather than a fixed count, so it is two columns on a 1080-wide phone and three or four on a tablet — the same width-driven behaviour as the services hub.
- **Each cell** is an `InkWell` over a card with the module-colour left rail, the record name (2 lines, ellipsis), a secondary line, and a status chip for parties. Tapping opens the same `PartyDetailScreen` / `MarketDetailScreen` the old preview rows did.
- **Scroll + refresh** belong to the grid, so `RefreshIndicator` wraps each tab's `GridView` instead of the page. Loading, error and empty states *replace* the grid rather than sitting inside it, so each fills its tab instead of floating in an empty scroll area.
- **List size**: `limit: 200` (API cap 500) instead of the default 100 — a grid is only worth having with more rows than that. Zone narrowing still runs in Dart *after* the fetch, never as a server-side `zone_id`.
- **Action bar**: Create / View-all move out of the cards into a `SafeArea` bar under the tabs. An `AnimatedBuilder` on the `TabController` re-labels them on swipe, so the pills name the tab actually on screen. Follow-ups joins that bar as an `AppIconTile` — it belongs to no single tab and must stay reachable from all three, but it no longer costs a row of grid height.
- **Pill labels flex.** `AppPillButton`'s label is `Flexible` + ellipsis, not a fixed-size `Text`. Sharing a row on a narrow handset previously overflowed by 4.5–15 px; the old card layout dodged that with a `Wrap`, which a pinned bar cannot use.

> **Why a `Column` and not a `CustomScrollView`.** The page has no scrolling content left — header, note, tab bar and action bar are all fixed, and the only scrollable is the grid inside `TabBarView`. A `TabBarView` also needs a bounded height, which `Expanded` supplies and a sliver would not.

### Earlier layout (v2.3.0+93)

One `TabController` drove a `TabBar` plus a fixed-height `TabBarView`, both inside the page's `CustomScrollView`. Superseded by the above.

### Pill actions (unchanged since v2.3.0+93)

The Create and View-all buttons were icon-only 36 dp squares whose meaning came from a tooltip. They are **icon + text pills** built from `AppPillButton`:

| Where | Label |
|---|---|
| Farms tab | **Add farm** / **All farms** |
| Dealers tab | **Add dealer** / **All dealers** |
| Markets tab | **Add market** / **All markets** |
| Party detail | **Post a visit** (filled) / **New follow-up** (tonal) |

`AppPillButton` lives in `lib/widgets/ui/app_pill_button.dart`:

- `filled: true` (default) is the primary action of a row — solid module colour, white glyph and label. `filled: false` is the secondary beside it — a 10% tint with a 25% border, label in the module colour.
- `minHeight: 44`. One dp under `AppButton`'s 48, because a pill shares a row rather than owning it.
- `dense: true` trims the horizontal padding, for the hub where two pills sit together.

> **Not changed:** the market detail screen's Edit button. It has no visit or follow-up action, so it was left alone rather than restyled on a guess.

---

## Feature flag

| Key | Default | Notes |
|-----|---------|-------|
| `marketing.enabled` | `true` | Fallback in `EndpointConfigService`; hub shows disabled state when off |

---

## Endpoint keys

All marketing paths resolve via `EndpointConfigService` (ZKTeco base). Fallbacks:

| Key | Method | Path |
|-----|--------|------|
| `marketing.markets` | GET/POST | `/api/v1/mobile/marketing/markets` |
| `marketing.dealers` | GET | `/api/v1/mobile/marketing/dealers?q=&limit=` |
| `marketing.market.create` | POST | `/api/v1/mobile/marketing/markets` |
| `marketing.market.nextCode` | GET | `/api/v1/mobile/marketing/markets/next-code?prefix=MRK` |
| `marketing.parties` | GET | `/api/v1/mobile/marketing/parties` |
| `marketing.party.create` | POST | `/api/v1/mobile/marketing/parties` |
| `marketing.party.nextCode` | GET | `/api/v1/mobile/marketing/parties/next-code?prefix=DLR\|FMR` |
| `marketing.visits` | GET | `/api/v1/mobile/marketing/visits` |
| `marketing.visit.create` | POST | `/api/v1/mobile/marketing/visits` |
| `marketing.visit.checkIn` | POST | `/api/v1/mobile/marketing/visits/{id}/check-in` |
| `marketing.visit.checkOut` | POST | `/api/v1/mobile/marketing/visits/{id}/check-out` |
| `marketing.surveys` | GET | `/api/v1/mobile/marketing/farm-surveys` (show: `GET …/farm-surveys/{id}`) |
| `marketing.survey.create` | POST | `/api/v1/mobile/marketing/farm-surveys` |
| `marketing.followups` | GET | `/api/v1/mobile/marketing/followups` |
| `marketing.followup.create` | POST | `/api/v1/mobile/marketing/followups` |
| `marketing.attachments` | POST | `/api/v1/mobile/marketing/attachments` |

Sales masters (party / market / visit Company / Sector dropdowns):

| Key | Method | Path |
|-----|--------|------|
| `sales.booking.formData` | GET | `{sales}/api/booking-person-books/form-data` |

Uses lists `data.feed.companyList` / `data.chicks.companyList` (merged) and `data.chicks.sectorList` (filtered by selected `companyId`). Bearer token required. Sector is optional when the company has no sectors. Demo catalog in `lib/data/marketing_demo_masters.dart` is used when Sales returns an empty list.

Auth headers for marketing: `Accept` + `User-Agent` only (no Bearer).

---

## Submit rules (avoid 422)

Opaque ints (`existing_dealer_id`, `product_id`, `unit_id`, `company_id`, `assigned_to_employee_id`, …) have **no ERP FK**. Demo IDs `>= 1` store fine.

These IDs **must exist in ZKTeco** or create fails:

- `market_id` → `exists:mkt_markets,id`
- `parent_party_id` / `party_id` / `dealer_party_id` → `exists:mkt_parties,id`
- `visit_id` → `exists:mkt_visits,id` (farm visit report omits this; backend creates a `visit_type=survey` row)

The app type-to-search **live** marketing lists for those. If the list is empty, the field is left unset. Fake market/party/visit IDs are never sent.

Server-generated `public_id` / `visit_no` stay off create forms. Visit `client_uuid` is auto-filled (`mkt-{hex}`, max 64) and shown read-only.

---

## Flows

### Create / edit market (market survey)

Searchable company, **zone**, and sector (all **read-only from the employee's scope** since v2.4.0+94); status `active` / `inactive`; name, **phone** (required + unique), **code** (allocated, read-only), geo address fields, notes, and a photo gallery. Market-intelligence fields: `feed_share_percent`, `chicks_share_percent`, `product_types` (multi-select chips), `feed_dealer_count`, `chicks_dealer_count`, `broiler_farm_count`, `layer_farm_count`, `color_farm_count`, `cock_farm_count`, plus dynamic **competitor rows** (`name` + `share_percent`). On open, app auto-fills `lat`/`lng` and best-effort geo/address from reverse geocode (editable). No Capture GPS button. → `POST /markets` create; **Edit market** on the detail screen → `PUT /markets/{id}` (partial fields; `updated_by_employee_id` stamped). There is **no market-visit flow** — markets are records, not visits.

> **Market photos (v2.4.0+94).** Uploads use `attachable_type=market`. This required widening the backend whitelist — `MktMarket` already declared an `attachments()` morph relation, but the type was rejected by validation.

### Create party (dealer / farm)

> **The farm form has moved.** It is no longer `PartyFormScreen(farm)` — see [Add Farm screen](#add-farm-screen) for its own search-first flow and field order. What follows describes the **dealer** form only.

1. Sections: Basic / Contact / Farm&Credit / Location / Products / Photos.
2. Payload **requires** `employee_id` (plus `created_by_employee_id` / `owner_employee_id`).
3. **Party type** offers two options (v2.4.0+94): **New dealer** → `dealer`, **Existing dealer** → `outlet`. Both were already in the API enum, so no backend change was needed to name them properly. The other enum values (`farmer`, `prospect`) remain valid in data and in existing records; they are just not something a field officer creates here.
4. **Code** is allocated server-side and read-only — see [Record codes](#record-codes). `_code` is only kept as a fallback for a hand-seeded value.
5. Scalars: `owner_name` (separate from contact person), `business_years`, `capacity_unit_id`, `existing_dealer_id` (existing dealers only).
6. Searchable: live parent dealer (farms), live Sales ERP dealer (existing dealers only — see [Existing dealer picker](#existing-dealer-picker)), product / category / unit / company per product row.
7. **Zone is read-only** from the employee's profile; **company, sector and market are the officer's own picks**, cascading company → sector → market — see [Organisational selection](#organisational-selection). **Phone** is required for every party and unique within its pool — see [Phone uniqueness](#phone-uniqueness).
8. Extra fields: email, alt phone, NID, trade license, `farm_type`, `capacity`, `credit_limit`, `payment_mode`, `lead_status`.
9. Product rows: relation types include `business`; searchable product (fills `product_name` + `product_id`); category, unit, company; `brand_name`, `monthly_quantity` / `current_stock`, `unit_price`, `competitor_company`, `is_our_product`, notes. A row is sent only when `product_name` is present.
10. Auto location on open → `lat`/`lng` + address prefill (editable). No Capture GPS button.
11. Optional multi-photo gallery → attachments `attachable_type=party`, WebP under `image[]`.

### Visit (dealer)

**Dealer visit** opens from a dealer record (`DealerVisitFormScreen`); the market-visit variant was removed in v2.3.0. Uses `POST /visits` with `status: in_progress`. Visit types: `regular`, `order`, `collection`, `technical_support`, `complaint`, `dealer_opening`, `other` — **not** `survey` (farm report only). Visit type field is type-to-search autocomplete.

Selecting a dealer **autofills market, company, and sector** from the party record when stored. Create with `status: in_progress` (not completed). Sends `visit_type`, live `market_id`, company/sector, `zone_id`/`zone_name` (party zone used as fallback server-side), `objective` / `purpose`, `findings`, **`feed_findings`**, **`chicks_findings`**, `result` / `outcome`, `next_plan`, `next_visit_date`, `order_amount`, `collection_amount`, auto-generated `client_uuid`, `geo_verified` (defaults true when GPS is present), check-in GPS.

Observation types: `uses|sells|stock|demand|order|competitor|sample|price|other`. Product row: searchable product + unit, brand, competitor, stock / demand / order qty, unit price, **amount** (auto: order qty × unit price; read-only), notes.

**At least one photo is required** to submit a dealer visit; photos upload as WebP under `image[]` via `uploadAttachments` (`attachable_type=visit`). If photo upload fails after the visit row is created, the visit is kept and flagged for retry on the detail screen (no duplicate create).

Check-in coords are auto-captured on form open (and retried on submit); no Check-in GPS button. After save, UI offers **Complete / check-out** → `POST .../check-out` with auto GPS (and optional findings/amounts). `completeVisit` in the service delegates to `checkOutVisit`.

### Farm visit report (farm survey)

Opened from a farm record (**Post a visit**). Title is **Farm visit report**. One `createFarmSurvey` call; if `visit_id` is omitted the backend creates a completed `mkt_visits` row (`visit_type=survey`) with check-in GPS when sent.

Read-only from the opened farm: farm name, owner, address, contact, **farming years**, **dealer name/address/contact** (from parent party — not editable). Date defaults to today (editable). Reporting officer is the logged-in profile name + designation.

Type-to-search autocomplete (`SearchableTextField`) for visit type, breed, DOC company, feed company, shed design, curtain, floor, territory, zone. Typed values are sent to existing string columns; suggestions from `marketing_demo_masters.dart`. Custom text allowed.

`dealer_party_id` and `farming_years` come from the farm party's parent dealer link and `business_years` — not from form pickers. Visit type and avg temperature range (e.g. `28-30`) store in `extra_data`. Detail screen shows those keys when present.

Computed when quantity + total mortality are filled: mortality % and rest of bird (read-only). When quantity + avg feed intake (g/bird) are filled: **total feed intake (kg)** = `quantity × avg_feed_intake_g / 1000` (read-only). Hatch date defaults to today; per bag weight defaults **50** kg. Flock field order: present mortality (today) → total mortality → mortality % / rest of bird → avg feed → total feed → total body weight → Production% / FCR → avg B/W → per bag weight. **Production% / FCR** is one form field (paper-aligned); values parse to `production_percent` / `fcr` with raw text in `extra_data.production_fcr_note`. Detail screen shows photo thumbnails from survey attachments. Ratings stay 1–5 (biosecurity, management, technical support, economical solvency). Photos use `attachable_type=survey`.

Paper field map: hatch / receiving date+time, breed, DOC + feed company, quantity, age, mortalities, rest of bird, feed intake (kg + avg g/bird), production% / FCR (single field), total + avg body weight (grams), bag weight, shed / curtain / floor / feeder / drinker / temp / space (sq ft), diseases, problems, remarks (`notes`), comments, territory, zone.

### Follow-up

Requires `title`; optional description, notes, `priority` (`low|medium|high|urgent`), `due_date`, `action_type`, status (default `open`). Searchable `assigned_to_employee_id` from the demo employee catalog. Searchable `visit_id` from **live** visits for that party (never a demo visit id). Optional photo gallery → `attachable_type=followup`. List mode shows status chips; tap open items to mark `completed` with optional `completion_note` via `updateFollowup`.

### Attachments (multipart)

Fields:

- `attachable_type` — `party` | `visit` | `survey` | `followup`
- `attachable_id`
- `employee_id` / `uploaded_by_employee_id`
- `image[]` — one or more **WebP** image files (compressed client-side via `ImageUploadService`; legacy `photos[]` / `image` still accepted server-side)

---

## Demo ID catalog

[`lib/data/marketing_demo_masters.dart`](../lib/data/marketing_demo_masters.dart)

| Picker | Demo examples |
|--------|----------------|
| ~~ERP dealers~~ | *removed — the picker is the live Sales master now* |
| Products | Peoples Feed Grower/Layer, Peoples DOC Chicks, Competitor Feed |
| Units | KG, Bag, Pcs, Ton, Acre, Decimal |
| Employees | Sales officer 1001–1003 |
| Companies / sectors | Peoples Poultry & Hatchery Ltd, Peoples Feed (used only when Sales form-data is empty) |
| Breed / DOC / feed / shed / curtain / floor | Cobb 500, Peoples Hatchery, Peoples Feed, Open / Semi-closed / Closed, … |
| Territory / zone | Munshiganj East, Dhaka South, … |

Selecting a product fills `product_name` and related category/company when those IDs match the catalog.

---

## App files

| Path | Role |
|------|------|
| `lib/models/marketing_models.dart` | Models + JSON helpers (camelCase API fields, zone + market intel) |
| `lib/models/auth_user_profile.dart` | Profile incl. `zoneId` / `zoneName` |
| `lib/models/booking_form_data_models.dart` | Sales form-data companies/sectors/zones |
| `lib/models/dealer_list_models.dart` | Sales `zoneList` (`DealerZone`) |
| `lib/data/marketing_demo_masters.dart` | Demo ERP-style IDs until live master APIs exist |
| `lib/utils/marketing_location_helper.dart` | Auto GPS + reverse geocode for forms |
| `lib/utils/multipart_form.dart` | Shared multipart builder (files supported) |
| `lib/services/image_upload_service.dart` | Image → compressed **WebP**, `image[]` parts |
| `lib/services/voice_typing_service.dart` | `speech_to_text` English/Bangla dictation |
| `lib/services/marketing_service.dart` | HTTP client (check-in/out, market update) |
| `lib/services/sales_service.dart` | `fetchBookingFormData()` + `fetchAllDealerLists()` + `fetchZoneList()` masters |
| `lib/models/zone_models.dart` | `SalesZone` / `ZoneDistrict` wire models for `get-zone` |
| `lib/models/zone_scope.dart` | `ZoneScope` — the resolved zone set and the `matches` predicate |
| `lib/widgets/ui/app_pill_button.dart` | `AppPillButton` — icon + label action used across the hub and party detail |
| `lib/widgets/ui/read_only_field.dart` | `ReadOnlyField` — a settled fact (zone, code, party type), shown locked |
| `lib/services/marketing_master_service.dart` | Company / sector / market lists for the cascading pickers; 24 h cache |
| `lib/services/marketing_service.dart` | HTTP client (`listExistingDealers`, `listFarms`, `nextCode`, `findPartiesByPhone`, `findMarketsByPhone`, `normalisePhone`, `samePhone`, check-in/out, market update) |
| `lib/models/marketing_dealer.dart` | `MarketingDealer` wire model for the ERP dealer picker |
| `lib/services/zone_scope_service.dart` | Resolves the profile's zone ids against the master; 24 h cache |
| `lib/widgets/searchable_select_field.dart` | Type-to-search dropdown (shared with Post booking) |
| `lib/widgets/voice_input_field.dart` | `VoiceTextField` + `VoiceMicButton` (mic on typed fields) |
| `lib/screens/marketing/*` | Hub cards, lists, market/party records, farm visit report, visit form |
| `lib/screens/marketing/farm_form_screen.dart` | `FarmFormScreen` — the standalone Add Farm screen (v2.5.3) |
| `test/farm_form_screen_test.dart` | Unit tests for the farm form's static rules |
| `lib/services/endpoint_config_service.dart` | Keys + `marketing.enabled` + `sales.booking.formData` |
| `lib/screens/employee_services_hub_screen.dart` | Services tile |

---

## List query params

| Resource | Params |
|----------|--------|
| Parties (master lists) | `party_type`, `market_id`, `q`, `status`, `limit` — **omit `employee_id`** so farms/dealers are company-wide for all authenticated users |
| Parties (optional mine filter) | `employee_id` still supported by the API when a private list is needed |
| Visits | `employee_id`, `party_id`, `status` |
| Farm surveys | `employee_id`, `party_id`, `from`, `to` |
| Follow-ups | `employee_id`, `party_id`, `status` |
| Markets | `q` — already company-wide |

Zone narrowing happens **client-side** after the response, not through a `zone_id` query param. See [Zone scoping](#zone-scoping).

Hub preview, View all parties, market-detail parties, and the parent-dealer picker **do not** send `employee_id`. Create still stamps `created_by_employee_id` / `owner_employee_id`.

---

## Zone scoping

### Where zones come from

Two services hold half the answer each, so the app joins them:

1. **HRM `pphl_erp`** — `GET /api/v1/get-my-info` returns `user.zoneId` as a **jsonb array** of ids (e.g. `[1, 2, 3]`). It carries **no names**, no FK and no validation. The app reads it into `AuthUserProfile.zoneIds`.
2. **Sales** — `GET /api/get-zone` (public, no auth) returns the zone master with each zone's **name** and its **districts**: `{ id, zoneName, zonalInCharge, districts: [{ id, name }], note }`.

`ZoneScopeService` resolves the profile's ids against that master and caches the result for 24 h. The cache is cleared on login and logout so one employee's zones never leak into another's session.

> **Why the app did not simply send `zone_id`.** The HRM array made the old `zone_id` param dead code: `int.tryParse("[1,2,3]")` returned `null`, so no zone filter was ever sent. That is fixed. But `zone_id` is still the wrong mechanism, for two reasons:
> - **It cannot express a union.** An employee in zones `[1,2,3]` needs all three in one list; `zone_id` takes a single value and would need three round-trips plus a merge.
> - **It would blank every existing row.** `mkt_markets` / `mkt_parties` / `mkt_visits` have nullable `zone_id` columns with **no backfill**, so a `zone_id=1` query returns only rows explicitly tagged zone 1 — and today that is nothing. The district fallback would have nothing left to rescue.
>
> So lists are fetched with their normal filters and narrowed in Dart. `zone_id` is still **written** on create/update so new rows get tagged going forward.

### The predicate

`ZoneScope.matches(zoneId:, zoneName:, district:)` keeps a row when **any** of these hold:

| Test | Why |
|------|-----|
| `zoneId` is one of the assigned zone ids | Row is explicitly tagged |
| `zoneName` matches an assigned zone name (case-insensitive) | **Zone names are the only cross-system join key** — zone ids are assigned independently by HRM, Sales and ZKTeco, so an id from one is not an id in another. The nested `zone.id` in `all-dealer-lists` is deliberately ignored. |
| `district` matches one of the assigned zones' districts | Rescues rows predating zone tagging, whose `zone_id` is `NULL` |

The district test uses **bidirectional containment** (`"dhaka"` vs `"dhaka division"`) because `mkt_markets.district` is free text, not a foreign key.

Parties carry no district of their own, so they inherit the district of the market they sit in. Visits carry no district either, so visits are matched on zone id and name only — **a visit predating zone tagging drops out of the visit list.**

### What is scoped

| Surface | Behaviour |
|---------|-----------|
| Marketing hub previews | Farms, dealers and markets, each the union of every assigned zone. A strip above them names the zones and lists their districts. |
| Markets / Parties list screens | Full lists, filtered. An empty result names the zones rather than looking like a loading bug. |
| Visits list | Filtered by zone id and name (no district available). |
| Market + Party create forms | **Zone is read-only**, resolved from the profile and matched **by name** to the `get-zone` master. Company / sector / market are the officer's own picks and are **not** zone-scoped — see [Organisational selection](#organisational-selection). |
| Party form market picker | Offers only the markets belonging to the **chosen sector**, not the employee's zone. |
| Post sale / Post booking / Receive payment | Dealer dropdowns scoped to the employee's zones **by zone name**. Dealers with no zone are kept — the payload cannot say which zone they belong to. |

The market form previously had **no** profile prefill while the party form did; both now prefill the zone by name.

### Graceful degradation

| Condition | Result |
|-----------|--------|
| Employee holds no zones (`zoneId: []`) | No chip, no filtering — exactly the pre-2.3.0+92 behaviour. |
| Zone master unreachable | Scope resolves to `null`, lists render unfiltered, no crash and no empty screen. |
| Profile holds an id the master does not know | That zone is skipped. If none resolve, unfiltered. |
| The list is empty after filtering | The empty state names the zones, so a short list reads as scope rather than as a bug. |

### Known limitation

District **spelling drift** between the Sales `districts` table and the free-text `mkt_markets.district` column can miss rows — `Bogura`/`Bogra`, `Barishal`/`Barisal`. Proper district filtering needs a `district_id` on the marketing tables plus a district master synced from Sales. Not addressed here; the ZKTeco side has no `districts` table at all today.

---

## Web Reports (ZKTeco)

Admin read-only pages (same Postgres `mkt_*` tables) live under **Reports** nested holders:

| Flutter | ZKTeco web |
|---------|------------|
| Markets list | `/reports/markets` |
| Market visits | `/reports/markets/visits` (trail map + visit grid; legacy visit rows — new market edits go through `PUT /markets/{id}`) |
| Dealers list | `/reports/dealers` |
| Dealer visits | `/reports/dealers/visits` |
| Farms list | `/reports/farms` |
| Farm visit reports | `/reports/farms/visits` |

See `zkteco-Automation-management-PPHL/docs/REPORTS.md`.

---

## Out of scope (later iterations)

- Document / signature / audio / video uploads (API is images-only)
- Live ERP dealer / product / employee APIs (replace demo catalog)
- Phase 2/3 tables (tour plans, targets, approval, questionnaire builder)
