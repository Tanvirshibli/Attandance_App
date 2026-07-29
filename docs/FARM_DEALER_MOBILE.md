# Farm & Dealer Mobile Module

Last updated: July 29, 2026

Field data collection for **dealers** and **farms** in Attandance_App, backed by ZKTeco `/api/v1/mobile/marketing/*` (no JWT — same pattern as geo). Employee identity uses profile `canonicalEmployeeId` (`employees.id`).

---

## Entry point

Services tab → **Farm & Dealer** → `MarketingHubScreen`

Hub tiles:

| Tile | Screen |
|------|--------|
| Dealers | `PartyListScreen(partyType: dealer)` |
| Farms | `PartyListScreen(partyType: farm)` |
| My visits | `VisitListScreen` |
| Follow-ups | `FollowupFormScreen` (list mode) |
| FAB New Dealer / New Farm | `PartyFormScreen` |

From party detail: **New Visit**, **Farm Survey** (farms), **Follow-up**, photo gallery.

---

## Feature flag

| Key | Default | Notes |
|-----|---------|-------|
| `marketing.enabled` | `true` | Fallback in `EndpointConfigService`; hub shows disabled state when off |

---

## Endpoint keys

All resolve via `EndpointConfigService` (ZKTeco base). Fallbacks:

| Key | Method | Path |
|-----|--------|------|
| `marketing.markets` | GET | `/api/v1/mobile/marketing/markets` |
| `marketing.parties` | GET | `/api/v1/mobile/marketing/parties` |
| `marketing.party.create` | POST | `/api/v1/mobile/marketing/parties` |
| `marketing.visits` | GET | `/api/v1/mobile/marketing/visits` |
| `marketing.visit.create` | POST | `/api/v1/mobile/marketing/visits` |
| `marketing.surveys` | GET | `/api/v1/mobile/marketing/farm-surveys` |
| `marketing.survey.create` | POST | `/api/v1/mobile/marketing/farm-surveys` |
| `marketing.followups` | GET | `/api/v1/mobile/marketing/followups` |
| `marketing.followup.create` | POST | `/api/v1/mobile/marketing/followups` |
| `marketing.attachments` | POST | `/api/v1/mobile/marketing/attachments` |

Complete visit uses `PUT {marketing.visits}/{id}` with `status: completed`.

Party detail uses `GET {marketing.parties}/{id}`.

Auth headers: `Accept` + `User-Agent` only (no Bearer).

---

## Flows

### Create party (dealer / farm)

1. Fill type, name, contact, phone, address, market dropdown, optional company/sector ids.
2. Capture GPS (Geolocator).
3. Optional product rows (name, demand, stock, competitor brand).
4. Optional multi-photo gallery (`image_picker` pickMultiImage).
5. `POST` party JSON → on success `POST` attachments multipart `photos[]`.

Example party payload:

```json
{
  "party_type": "dealer",
  "name": "ABC Feed",
  "trade_name": "ABC",
  "contact_person": "Karim",
  "phone": "01700000000",
  "address": "…",
  "market_id": 1,
  "company_id": 2,
  "sector_id": 3,
  "created_by_employee_id": 42,
  "owner_employee_id": 42,
  "lat": 23.81,
  "lng": 90.41,
  "status": "active",
  "notes": "…",
  "products": [
    {
      "product_name": "Layer feed",
      "demand_qty": 100,
      "stock_qty": 20,
      "competitor_brand": "OtherCo"
    }
  ]
}
```

### Visit

```json
{
  "party_id": 10,
  "employee_id": 42,
  "visit_date": "2026-07-29",
  "check_in_at": "2026-07-29T12:00:00.000",
  "check_in_lat": 23.81,
  "check_in_lng": 90.41,
  "purpose": "Stock check",
  "outcome": "Order promised",
  "status": "completed",
  "products": [
    { "product_name": "Layer feed", "observed_stock": 15, "order_qty": 50 }
  ]
}
```

Then multipart photos with `attachable_type=visit`.

### Farm survey

```json
{
  "party_id": 11,
  "employee_id": 42,
  "survey_date": "2026-07-29",
  "farm_type": "Broiler",
  "bird_capacity": 5000,
  "current_birds": 4200,
  "housing_type": "Closed",
  "feed_brand": "PPHL",
  "status": "submitted",
  "metrics": [
    { "metric_key": "flock_age_days", "metric_label": "Flock age", "value_number": 28, "unit": "days" },
    { "metric_key": "mortality_pct", "metric_label": "Mortality", "value_number": 1.2, "unit": "%" },
    { "metric_key": "feed_bag_stock", "metric_label": "Feed bag stock", "value_number": 40, "unit": "bags" }
  ]
}
```

### Follow-up

```json
{
  "party_id": 10,
  "employee_id": 42,
  "action_type": "Call back",
  "due_date": "2026-08-01",
  "priority": "high",
  "status": "open",
  "notes": "…"
}
```

### Attachments (multipart)

Fields:

- `attachable_type` — `party` | `visit` | `farm_survey` | `followup`
- `attachable_id`
- `employee_id` / `uploaded_by_employee_id`
- `photos[]` — one or more image files (backend converts to WebP)

---

## App files

| Path | Role |
|------|------|
| `lib/models/marketing_models.dart` | Models + JSON helpers |
| `lib/services/marketing_service.dart` | HTTP client |
| `lib/screens/marketing/*` | Hub, lists, forms, detail |
| `lib/services/endpoint_config_service.dart` | Keys + `marketing.enabled` |
| `lib/screens/employee_services_hub_screen.dart` | Services tile |

---

## List query params

| Resource | Params |
|----------|--------|
| Parties | `employee_id`, `party_type`, `q`, `status` |
| Visits | `employee_id`, `party_id`, `status` |
| Follow-ups | `employee_id`, `party_id`, `status` |
| Markets | `q` (optional) |
