# Farm & Dealer Mobile Module

Last updated: August 22, 2026

Field data collection for **markets**, **dealers**, and **farms** in Attandance_App, backed by ZKTeco `/api/v1/mobile/marketing/*` (no JWT — same pattern as geo). Employee identity uses profile `canonicalEmployeeId` (`employees.id`).

**v2.2.3+64:** Markets hub panel uses purple (`AppColors.secondary`) so it is visually distinct from Dealers (blue primary). Previous builds used `AppColors.info`, which matched primary at low tint.

**v2.2.3+63:** Hub sections use distinct tinted panels (Farms green, Dealers primary blue, Markets purple). Farm visit report accepts **free-text** breed, DOC/feed company, shed, curtain, floor, territory, and zone with demo suggestion chips (CB, Provita, PPHL, Open shed, Cloth, Concrete house, zones A/B/C, etc.). Labels clarify units (avg feed g/bird, avg B/W grams, space sq ft). Editable farming years; visit type and temperature range stored in `extra_data`. Home Recent Attendance badge no longer overlaps check-in/out times.

**v2.2.3+61:** Renamed to **Farms, Dealers and Markets**. Hub sections (Farms → Dealers → Markets) show top **5** preview rows; compact **Create** (+) and **View all** (list) icon buttons sit on the title row. Tap a preview row for the record page; pull-to-refresh reloads previews.

**v2.2.3+60:** Farm & Dealer hub uses expandable **Create** / **View all** cards (no FABs, no standalone Visits tile). Farm records open the paper **Farm visit report** (rewritten farm survey). Dealer records still use the stock/order visit form. Posting a visit lives on the farm or dealer record page.

**v2.2.3+59:** Create forms collect the full Phase-1 field set the current marketing API already accepts. ID fields are type-to-search (`SearchableSelectField`). Live lists are used for markets, parties, and visits (FK-checked). Demo catalog fills ERP-style IDs (dealers, products, units, employees) until live master APIs exist. Company / sector prefer Sales `GET /api/booking-person-books/form-data` (Bearer); demo companies/sectors fill the picker when that list is empty.

Create forms auto-capture GPS + reverse-geocode address fields (no manual Capture GPS buttons). Attachments stay **photos only** (`photos[]` images → WebP). Documents, signature, audio, and video wait for a later API.

---

## Entry point

Services tab → **Farms, Dealers and Markets** → `MarketingHubScreen`

Hub sections (Farms → Dealers → Markets). Each section title row has compact **Create** (+) and **View all** (list) icon buttons on the right. Below: up to **5** recent preview rows (tap → record detail). **View all** opens the full list screen.

| Section | Create | View all | Preview tap |
|---------|--------|----------|-------------|
| Farms | `PartyFormScreen(farm)` | `PartyListScreen(farm)` | `PartyDetailScreen` → Post visit report |
| Dealers | `PartyFormScreen(dealer)` | `PartyListScreen(dealer)` | `PartyDetailScreen` → Post visit |
| Markets | `MarketFormScreen` | `MarketListScreen` | `MarketDetailScreen` |
| Follow-ups | — | `FollowupFormScreen` (list mode) | — |

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
| `marketing.parties` | GET | `/api/v1/mobile/marketing/parties` |
| `marketing.party.create` | POST | `/api/v1/mobile/marketing/parties` |
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

### Create market

Searchable company and sector; status `active` / `inactive`; name, code, geo address fields, notes. On open, app auto-fills `lat`/`lng` and best-effort geo/address from reverse geocode (editable). No Capture GPS button. → `POST /markets` with `company_id` / `sector_id` when selected.

### Create party (dealer / farm)

1. Sections: Basic / Contact / Farm&Credit / Location / Products / Photos.
2. Payload **requires** `employee_id` (plus `created_by_employee_id` / `owner_employee_id`).
3. Scalars: `code`, `owner_name` (separate from contact person), `business_years`, `capacity_unit_id`, `existing_dealer_id`.
4. Searchable: live market, live parent dealer (farms), company/sector (Sales then demo), existing ERP dealer (demo).
5. Extra fields: email, alt phone, NID, trade license, `farm_type`, `capacity`, `credit_limit`, `payment_mode`, `lead_status`.
6. Product rows: relation types include `business`; searchable product (fills `product_name` + `product_id`); category, unit, company; `brand_name`, `monthly_quantity` / `current_stock`, `unit_price`, `competitor_company`, `is_our_product`, notes. A row is sent only when `product_name` is present.
7. Auto location on open → `lat`/`lng` + address prefill (editable). No Capture GPS button.
8. Optional multi-photo gallery → attachments `attachable_type=party`.

### Visit

Create with `status: in_progress` (not completed). Sends `visit_type`, live `market_id`, company/sector, `objective` / `purpose`, `findings`, `result` / `outcome`, `next_plan`, `next_visit_date`, `order_amount`, `collection_amount`, auto-generated `client_uuid`, `geo_verified` (defaults true when GPS is present), check-in GPS.

Observation types: `uses|sells|stock|demand|order|competitor|sample|price|other`. Product row: searchable product + unit, brand, competitor, quantity / demand / stock, unit price, amount, notes.

Check-in coords are auto-captured on form open (and retried on submit); no Check-in GPS button. After save, UI offers **Complete / check-out** → `POST .../check-out` with auto GPS (and optional findings/amounts). `completeVisit` in the service delegates to `checkOutVisit`.

### Farm visit report (farm survey)

Opened from a farm record (**Post a visit**). Title is **Farm visit report**. One `createFarmSurvey` call; if `visit_id` is omitted the backend creates a completed `mkt_visits` row (`visit_type=survey`) with check-in GPS when sent.

Read-only from the opened farm: farm name, owner, address, contact, farming years. Date defaults to today (editable). Reporting officer is the logged-in profile name. Dealer name/address/contact prefills from the parent dealer when present; otherwise a searchable **live** dealer list (never a fake `dealer_party_id`).

Free-text fields with demo suggestion chips: visit type, breed, DOC company, feed company, shed design, curtain, floor, territory, zone. Typed values are sent to the existing string columns (`breed`, `doc_company`, `feed_company`, etc.); chips come from `marketing_demo_masters.dart` (CB, Provita, PPHL, Open shed, Cloth, Concrete house, zones A/B/C, …).

Editable **farming years** on the visit form (not read-only from party). Reporting officer shows profile name + designation. Visit type and avg temperature range (e.g. `28-30`) store in `extra_data` (`visit_type_label`, `avg_temperature_note`, `reporting_officer_designation`). Detail screen shows those keys when present.

Computed when quantity + total mortality are filled: mortality % and rest of bird (user can override). Ratings stay 1–5 (biosecurity, management, technical support, economical solvency). Photos use `attachable_type=survey`.

Paper field map: hatch / receiving date+time, breed, DOC + feed company, quantity, age, mortalities, rest of bird, feed intake (kg + avg g/bird), production %, FCR, total + avg body weight (grams), bag weight, shed / curtain / floor / feeder / drinker / temp / space (sq ft), diseases, problems, remarks (`notes`), comments, territory, zone.

### Follow-up

Requires `title`; optional description, notes, `priority` (`low|medium|high|urgent`), `due_date`, `action_type`, status (default `open`). Searchable `assigned_to_employee_id` from the demo employee catalog. Searchable `visit_id` from **live** visits for that party (never a demo visit id). Optional photo gallery → `attachable_type=followup`. List mode shows status chips; tap open items to mark `completed` with optional `completion_note` via `updateFollowup`.

### Attachments (multipart)

Fields:

- `attachable_type` — `party` | `visit` | `survey` | `followup`
- `attachable_id`
- `employee_id` / `uploaded_by_employee_id`
- `photos[]` — one or more image files (backend converts to WebP)

---

## Demo ID catalog

[`lib/data/marketing_demo_masters.dart`](../lib/data/marketing_demo_masters.dart)

| Picker | Demo examples |
|--------|----------------|
| ERP dealers | Bismillah PPHL Feed, Sunrise Agro Store, City Farm Depot |
| Products | Peoples Feed Grower/Layer, Peoples DOC Chicks, Competitor Feed |
| Units | KG, Bag, Pcs, Acre, Decimal |
| Employees | Sales officer 1001–1003 |
| Companies / sectors | Peoples Poultry & Hatchery Ltd, Peoples Feed (used only when Sales form-data is empty) |
| Breed / DOC / feed / shed / curtain / floor | Cobb 500, Peoples Hatchery, Peoples Feed, Open / Semi-closed / Closed, … |
| Territory / zone | Munshiganj East, Dhaka South, … |

Selecting a product fills `product_name` and related category/company when those IDs match the catalog.

---

## App files

| Path | Role |
|------|------|
| `lib/models/marketing_models.dart` | Models + JSON helpers (camelCase API fields) |
| `lib/models/booking_form_data_models.dart` | Sales form-data companies/sectors |
| `lib/data/marketing_demo_masters.dart` | Demo ERP-style IDs until live master APIs exist |
| `lib/utils/marketing_location_helper.dart` | Auto GPS + reverse geocode for forms |
| `lib/services/marketing_service.dart` | HTTP client (check-in/out, update party/followup) |
| `lib/services/sales_service.dart` | `fetchBookingFormData()` for company/sector masters |
| `lib/widgets/searchable_select_field.dart` | Type-to-search dropdown (shared with Post booking) |
| `lib/screens/marketing/*` | Hub cards, lists, market/party records, farm visit report, visit form |
| `lib/services/endpoint_config_service.dart` | Keys + `marketing.enabled` + `sales.booking.formData` |
| `lib/screens/employee_services_hub_screen.dart` | Services tile |

---

## List query params

| Resource | Params |
|----------|--------|
| Parties | `employee_id`, `party_type`, `market_id`, `q`, `status` |
| Visits | `employee_id`, `party_id`, `status` |
| Farm surveys | `employee_id`, `party_id`, `from`, `to` |
| Follow-ups | `employee_id`, `party_id`, `status` |
| Markets | `q` (optional) |

---

## Out of scope (later iterations)

- Document / signature / audio / video uploads (API is images-only)
- Live ERP dealer / product / employee APIs (replace demo catalog)
- Phase 2/3 tables (tour plans, targets, approval, questionnaire builder)
