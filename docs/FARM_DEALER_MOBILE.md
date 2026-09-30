# Farm & Dealer Mobile Module

Last updated: September 30, 2026 — **v2.4.0+94**

Field data collection for **markets**, **dealers**, and **farms** in Attandance_App, backed by ZKTeco `/api/v1/mobile/marketing/*` (no JWT — same pattern as geo). Employee identity uses profile `canonicalEmployeeId` (`employees.id`).

**v2.4.0+94: Full-screen grids, employee-scoped read-only fields, generated codes.**
The hub's three module cards are replaced by one full-height grid per tab with a pinned action bar. Zone / company / sector / market on all three forms are derived from the logged-in employee and shown read-only. Dealer / farm / market codes are allocated server-side (`DLR-09260001`). Phone is required and unique per dealer and per market. See [Hub layout](#hub-layout), [Auto-scoped read-only fields](#auto-scoped-read-only-fields), [Record codes](#record-codes), [Phone uniqueness](#phone-uniqueness).

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
| Farms | `PartyFormScreen(farm)` | `PartyListScreen(farm)` | `PartyDetailScreen` → Post visit report |
| Dealers | `PartyFormScreen(dealer)` | `PartyListScreen(dealer)` | `PartyDetailScreen` → Post visit |
| Markets | `MarketFormScreen` | `MarketListScreen` | `MarketDetailScreen` → Post visit |
| *(below the tabs)* Follow-ups | — | `FollowupFormScreen` (list mode) | — |

| Visit entry | Screen | API |
|-------------|--------|-----|
| Farm party → Post a visit | `FarmSurveyFormScreen` | `POST /farm-surveys` |
| Dealer party → Post a visit | `DealerVisitFormScreen` | `POST /visits` |
| Market detail → Post a visit | `MarketVisitFormScreen` (pick party in market) | `POST /visits` |

---

## Auto-scoped read-only fields

**v2.4.0+94.** The dealer, farm and market forms used to ask a field officer to pick their own **zone, company, sector and market**. Nothing stopped them choosing a neighbouring one, and every marketing list filters on those columns — so a wrong pick silently filed the record where the officer would not expect to find it. All four are now derived from the logged-in employee.

`EmployeeMarketingScopeService` (`lib/services/employee_marketing_scope_service.dart`) resolves them once and the three forms share the answer:

| Field | Resolved from | Join |
|---|---|---|
| **Zone** | HRM `user.zoneId` → Sales zone master | **by name**, never by id |
| **Company** | profile `sector` → Sales `form-data` `companyList` | exact name, then prefix |
| **Sector** | profile `sector` → Sales `form-data` `sectorList` | exact name, then prefix |
| **Market** | nearest market in the zone to the form's own GPS fix | zone id, zone name, then district |

- **Company/sector match exact first, then prefix.** A plain `contains` would let the profile's `"Peoples Feed"` resolve to `"Peoples Feed (Chicks)"` while the real company sat later in the list.
- **Exact-then-prefix matters because ids are not portable.** HRM, Sales and ZKTeco each assign zone / company / sector ids independently, so an id from one system means nothing in another. Same rule as the zone scoping below.
- **Market is the nearest one, not the first row.** This is the one field with no single right answer: a zone normally holds several markets and the officer is the one who knows which they are standing in. Resolving by GPS proximity is defensible; "first row" would file dealers under the wrong market with no way to notice. It stays read-only but is **visible**, so a mis-resolution can be reported instead of being buried in the payload.
- **Caching**: 24 h in `SharedPreferences`, same TTL pattern as `ZoneScopeService`, cleared on login and logout so one employee's scope never leaks into another's session.

### Graceful degradation

| Condition | Result |
|---|---|
| A field resolves | Value shown, id written to the payload |
| A field does not resolve | *"Not set — ask an admin to set your zone"* / *"Unresolved from your profile"*, and **the key is omitted** |
| Dealer with **no** resolvable zone | Submit blocked with a clear message — never saved untagged |
| Zone master or Sales unreachable | Everything resolves to null; the form still works, just unscoped |

> **Never send a guessed id.** A wrong `company_id` files a dealer under another company — a silent data error an admin has to find and undo. An empty column is visible and correctable, so unresolved means omitted, never defaulted.

### Rendering

`ReadOnlyField` (`lib/widgets/ui/read_only_field.dart`): a sunk `AppColors.surfaceSunk` box, `AppColors.inkFaint` text, **no mic**, **no tap handler**, and a small `Icons.lock_outline` suffix. A `SearchableSelectField` with `enabled: false` would still render as a field you could tap; this renders as a settled fact.

The farm visit report's **Zone** is read-only on the same terms, with one difference: **the farm's own zone wins** when it has one (the report is about that farm, not the officer), falling back to the officer's scope for a farm created before zone tagging.

**Still editable:** parent dealer on a farm, the market on an *edit* form, and every contact / credit / location / product field. A farm's dealer relationship is field knowledge, not an HRM attribute — deriving it from the employee's territory would be a guess.

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

**v2.4.0+94.** A dealer is identified by its phone number, so one number belongs to one dealer.

| Field | Required | Unique |
|---|---|---|
| Dealer / existing dealer | yes | yes |
| Market | yes | yes |
| Farm | no | yes, when given |

> **Why farms are exempt.** Farms share `mkt_parties` with dealers but are not looked up by number, so inheriting the dealer requirement would block legitimate farm records. The server enforces the same split via `Rule::requiredIf` on `party_type`.

Three layers, because the client cannot be the authority:

1. **Debounced client check.** `GET /parties?q=<digits>` on a 700 ms debounce while typing, and again on submit (the debounce can lag an edit). The backend `q` filter is a substring `LIKE`, so **every hit is compared after normalisation** — comparing raw strings would let `01712-345678`, `+8801712345678` and `01712345678` register as three different dealers.
2. **`MarketingService.normalisePhone` / `samePhone`.** Strips spaces, dashes and parentheses, drops a `+88` / `0088` country code, then a national leading `0`. An empty or missing phone never matches anything.
3. **Server `unique` rule + partial unique index.** The client's early warning is a convenience; the 422 is the enforcement. A clash shows as *"Already linked to <name> (<code>)"* rather than a raw validation blob.

**A failed lookup is not a pass.** It only means the early warning is unavailable — the submit still goes out and is still validated by the server.

`mkt_parties.phone` gets a unique index **over live rows only** (`WHERE phone IS NOT NULL AND deleted_at IS NULL`), because the model uses `SoftDeletes` and a deleted dealer must not hold their number hostage. `mkt_markets` has no soft deletes, so its index has no such clause. Where pre-existing duplicates would make the DDL fail, the index is skipped rather than blocking the deploy — the API-level validation still keeps new rows correct.

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

1. Sections: Basic / Contact / Farm&Credit / Location / Products / Photos.
2. Payload **requires** `employee_id` (plus `created_by_employee_id` / `owner_employee_id`).
3. **Party type** offers two options (v2.4.0+94): **New dealer** → `dealer`, **Existing dealer** → `outlet`. Both were already in the API enum, so no backend change was needed to name them properly. A farm screen shows its type read-only. The other enum values (`farmer`, `prospect`) remain valid in data and in existing records; they are just not something a field officer creates here.
4. **Code** is allocated server-side and read-only — see [Record codes](#record-codes). `_code` is only kept as a fallback for a hand-seeded value.
5. Scalars: `owner_name` (separate from contact person), `business_years`, `capacity_unit_id`, `existing_dealer_id`.
6. Searchable: live parent dealer (farms), existing ERP dealer (demo catalog), product / category / unit / company per product row.
7. **Zone / company / sector / market are read-only** from the employee's scope — see [Auto-scoped read-only fields](#auto-scoped-read-only-fields). **Phone** is required for dealers and unique — see [Phone uniqueness](#phone-uniqueness).
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
| ERP dealers | Bismillah PPHL Feed, Sunrise Agro Store, City Farm Depot |
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
| `lib/widgets/ui/read_only_field.dart` | `ReadOnlyField` — a value the app derived, shown locked |
| `lib/services/employee_marketing_scope_service.dart` | Resolves zone / company / sector / market from the employee; 24 h cache |
| `lib/services/marketing_service.dart` | HTTP client (`nextCode`, `findPartiesByPhone`, `findMarketsByPhone`, `normalisePhone`, `samePhone`, check-in/out, market update) |
| `lib/services/zone_scope_service.dart` | Resolves the profile's zone ids against the master; 24 h cache |
| `lib/widgets/searchable_select_field.dart` | Type-to-search dropdown (shared with Post booking) |
| `lib/widgets/voice_input_field.dart` | `VoiceTextField` + `VoiceMicButton` (mic on typed fields) |
| `lib/screens/marketing/*` | Hub cards, lists, market/party records, farm visit report, visit form |
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
| Market + Party create forms | Zone picker options come from `get-zone`; pre-seeded to the employee's first assigned zone, matched **by name**. |
| Party form market picker | Offers only markets inside the selected zone (name-matched, using that zone's district list). |
| Post sale / Post booking / Receive payment | Dealer dropdowns scoped to the employee's zones **by zone name**. Dealers with no zone are kept — the payload cannot say which zone they belong to. |

The market form previously had **no** profile prefill while the party form did; both now prefill by name.

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
