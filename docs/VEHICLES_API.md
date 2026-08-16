# Vehicles API (Transport)

**App:** Attandance_App — Services → **Vehicles**  
**Host default:** `https://transport.peoplesitsolution.online`  
**Auth:** none (open GET, same as other transport GETs)  
**Feature flag:** ZKTeco `feature.vehicle.enabled` / app `vehicle.enabled`

No employee filter. The app shows **all** active vehicles, **all** maintenance jobs for a vehicle, and **all** trips for that vehicle.

```
Services Vehicles → fleet list → vehicle hub (Maintenance | Trips)
```

## 1. Active vehicle list

`GET {TRANSPORT_API_BASE_URL}/api/get-vehicle-active-list`

App config key: `vehicle.list`

```json
{
  "success": true,
  "data": [
    {
      "id": 34,
      "tVehicleNo": "DM-DA-12-6403",
      "purchaseDate": "2025-05-19",
      "numberPlate": "DM-DA-12-6403"
    }
  ]
}
```

List row: plate, purchase date, `tVehicleNo` when it differs from the plate. Tap a row → vehicle hub.

## 2. Vehicle hub

No extra HTTP. Two tiles:

- **Maintenance** → history for this vehicle
- **Trips** → trips for this vehicle

## 3. Maintenance history

`GET {TRANSPORT_API_BASE_URL}/api/get-vehicle-m-history/{vehicleId}`

App config key: `vehicle.maintenance` (app appends `/{id}`).

```json
{
  "success": true,
  "message": "Vehicle last five maintenance jobs loaded successfully.",
  "vehicleId": 34,
  "total": 2,
  "data": {
    "maintenanceInfo": [
      {
        "id": 175,
        "date": "2026-07-23",
        "job_no": "VMJ26070175",
        "job_title": "Wearing",
        "status": "completed",
        "grand_total": 192.73,
        "workshop": "Tanglail Workshop",
        "parts": []
      }
    ]
  }
}
```

## 4. Trips for this vehicle

`GET {TRANSPORT_API_BASE_URL}/api/get-trips-list?page={n}&vehicle_id={vehicleId}`

App config key: `vehicle.trips`

Laravel paginator (`data[]`, `links`, `meta`, `success`). Sample page 1: **200** trips, **897** total, `per_page` 200. `meta.totalStatus`: all / archived / draft / inTransit / cancelled / delivered.

`vehicle_id` is sent; the server may ignore it. The app still **filters client-side** to trips where `vehicle.vehicle.id` equals the selected vehicle. **No** `employee_id` and **no** driver/helper filter.

Pagination: first page for a fast paint, then Load more / scroll until `meta.current_page` == `meta.last_page`. Status chips: All, In transit, Delivered, Draft, Cancelled, Archived.

Tap a trip → detail from the same object (no second HTTP). Summaries only: route, vehicle/crew, cargo, customer, fuel, totals, advances, note.

## Out of scope

- No POST/edit of trips or maintenance
- No employee-scoped filtering
