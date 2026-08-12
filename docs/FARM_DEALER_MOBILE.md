# Farm & Dealer Mobile Module

Last updated: August 9, 2026

Field data collection for **markets**, **dealers**, and **farms** in Attandance_App, backed by ZKTeco `/api/v1/mobile/marketing/*` (no JWT — same pattern as geo). Employee identity uses profile `canonicalEmployeeId` (`employees.id`).

Company / sector dropdowns on party create load from Sales `GET /api/booking-person-books/form-data` (Bearer). Create forms auto-capture GPS + reverse-geocode address fields (no manual Capture GPS buttons).

---

## Entry point

Services tab → **Farm & Dealer** → `MarketingHubScreen`

Hub tiles:

| Tile | Screen |
|------|--------|
| Markets | `MarketListScreen` → create via `MarketFormScreen` |
| Dealers | `PartyListScreen(partyType: dealer)` |
| Farms | `PartyListScreen(partyType: farm)` |
| Visits | `VisitListScreen` |
| Follow-ups | `FollowupFormScreen` (list mode) |
| FAB New Dealer / New Farm / New Market | `PartyFormScreen` / `MarketFormScreen` |

From party detail: **New Visit**, **Farm Survey** (farms), **Follow-up**, photo gallery.

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
| `marketing.surveys` | GET | `/api/v1/mobile/marketing/farm-surveys` |
| `marketing.survey.create` | POST | `/api/v1/mobile/marketing/farm-surveys` |
| `marketing.followups` | GET | `/api/v1/mobile/marketing/followups` |
| `marketing.followup.create` | POST | `/api/v1/mobile/marketing/followups` |
| `marketing.attachments` | POST | `/api/v1/mobile/marketing/attachments` |

Sales masters (party Company / Sector dropdowns):

| Key | Method | Path |
|-----|--------|------|
| `sales.booking.formData` | GET | `{sales}/api/booking-person-books/form-data` |

Uses lists `data.feed.companyList` / `data.chicks.companyList` (merged) and `data.chicks.sectorList` (filtered by selected `companyId`). Bearer token required. Sector is optional when the company has no sectors.

Auth headers for marketing: `Accept` + `User-Agent` only (no Bearer).

---

## Flows

### Create market

Name, code, division / district / upazila / union / village, notes. On open, app auto-fills `lat`/`lng` and best-effort geo/address from reverse geocode (editable). No Capture GPS button. → `POST /markets`.

### Create party (dealer / farm)

1. Sections: Basic / Contact / Farm&Credit / Location / Products / Photos.
2. Payload **requires** `employee_id` (plus `created_by_employee_id` / `owner_employee_id`).
3. **Company** / **Sector** dropdowns from Sales form-data → payload `company_id` / `sector_id`.
4. Extra fields: email, alt phone, NID, trade license, `parent_party_id` (farm → dealer), `farm_type`, `capacity`, `credit_limit`, `payment_mode`, `lead_status`.
5. Product rows: `relation_type` (`stock|demand|sells|uses|competitor`), `competitor_company`.
6. Auto location on open → `lat`/`lng` + address prefill (editable). No Capture GPS button.
7. Optional multi-photo gallery → attachments `attachable_type=party`.

### Visit

Create with `status: in_progress` (not completed). Sends `visit_type`, `market_id`, `objective`, `findings`, `result`, `next_plan`, `next_visit_date`, `order_amount`, `collection_amount`, check-in GPS. Product lines include `observation_type`.

Check-in coords are auto-captured on form open (and retried on submit); no Check-in GPS button. After save, UI offers **Complete / check-out** → `POST .../check-out` with auto GPS (and optional findings/amounts). `completeVisit` in the service delegates to `checkOutVisit`.

### Farm survey

Analytical fields: `age_days`, `quantity`, `mortality_quantity`, `chicks_brand`, feed intake, `fcr`, body weight, uniformity, ratings 1–5 (biosecurity / management / technical / economic), disease toggle + details, problems, recommendation; legacy metrics rows kept. Photos use `attachable_type=survey` (not `farm_survey`). Optional `visitId` from constructor.

### Follow-up

Requires `title`; optional description, `priority` (`low|medium|high|urgent`), `due_date`, `action_type`. List mode shows status chips; tap open items to mark `completed` with optional `completion_note` via `updateFollowup`.

### Attachments (multipart)

Fields:

- `attachable_type` — `party` | `visit` | `survey` | `followup`
- `attachable_id`
- `employee_id` / `uploaded_by_employee_id`
- `photos[]` — one or more image files (backend converts to WebP)

---

## App files

| Path | Role |
|------|------|
| `lib/models/marketing_models.dart` | Models + JSON helpers (camelCase API fields) |
| `lib/models/booking_form_data_models.dart` | Sales form-data companies/sectors |
| `lib/utils/marketing_location_helper.dart` | Auto GPS + reverse geocode for forms |
| `lib/services/marketing_service.dart` | HTTP client (check-in/out, update party/followup) |
| `lib/services/sales_service.dart` | `fetchBookingFormData()` for company/sector masters |
| `lib/screens/marketing/*` | Hub, lists, forms, detail |
| `lib/services/endpoint_config_service.dart` | Keys + `marketing.enabled` + `sales.booking.formData` |
| `lib/screens/employee_services_hub_screen.dart` | Services tile |

---

## List query params

| Resource | Params |
|----------|--------|
| Parties | `employee_id`, `party_type`, `q`, `status` |
| Visits | `employee_id`, `party_id`, `status` |
| Follow-ups | `employee_id`, `party_id`, `status` |
| Markets | `q` (optional) |
