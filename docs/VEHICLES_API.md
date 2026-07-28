# Vehicles API (Transport)

**App:** Attandance_App — Services → Vehicles  
**Host default:** `https://transport.peoplesitsolution.online`  
**Auth:** none (open GET)  
**Feature flag:** ZKTeco `feature.vehicle.enabled` / app `vehicle.enabled`

## List

`GET {TRANSPORT_API_BASE_URL}/api/get-vehicle-active-list`

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

App config key: `vehicle.list`

## Maintenance history

`GET {TRANSPORT_API_BASE_URL}/api/get-vehicle-m-history/{vehicleId}`

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
        "job_type": "external",
        "issue_type": "External Problem (Light, Wiper, Wheel)",
        "status": "completed",
        "labor_cost": 0,
        "parts_cost": 192.73,
        "grand_total": 192.73,
        "workshop": "Tanglail Workshop",
        "parts": [
          {
            "id": 359,
            "part_id": 574,
            "name": "Parking light Bulb",
            "unit": "Piece",
            "qty": 3,
            "price": 20.08,
            "total_price": 60.24
          }
        ]
      }
    ]
  }
}
```

App config key: `vehicle.maintenance` (app appends `/{id}`).
