# Backend Target Models (Final)

Last updated: 2026-03-01  
Scope: final structures for `new_attendance_requests`, `new_attendance_devices`, and new `face_registration_android` so Android app + ZKTeco ADMS can run on the same backend.

Implementation update (2026-03-05): mobile APIs are now active in `pphl_erp` for face registration upsert/fetch and attendance request submit/list. The Android app now uses these endpoints in production flow.

---

## 1) `new_attendance_requests` (final)

This table structure should remain aligned with your existing ERP migration and DB screenshot.

### Purpose
- Stores attendance requests from users/admin (self punch, manual attendance, punch correction).
- Works as approval queue before final attendance posting.

### Columns

| Column | Type | Null | Default | Key/Index | Notes |
|---|---|---|---|---|---|
| id | bigint unsigned | No | AUTO_INCREMENT | PK | Primary key |
| companyId | bigint unsigned | Yes | NULL | INDEX | Company scope |
| sectorId | bigint unsigned | Yes | NULL | INDEX | Sector/department scope |
| shiftId | bigint unsigned | Yes | NULL | INDEX | Requested shift |
| employeeId | bigint unsigned | Yes | NULL | INDEX | Request owner |
| attDate | date | No | — | INDEX | Attendance date |
| requestType | enum('self_punch','manual_attendance','punch_correction') | No | — | INDEX | Request category |
| requestedInTime | datetime | Yes | NULL | — | Requested in time |
| requestedOutTime | datetime | Yes | NULL | — | Requested out time |
| lat | decimal(10,7) | Yes | NULL | — | Geo evidence (mobile/self) |
| lng | decimal(10,7) | Yes | NULL | — | Geo evidence (mobile/self) |
| address | varchar(255) | Yes | NULL | — | Reverse-geocoded address |
| photoPath | varchar(255) | Yes | NULL | — | Optional proof image path |
| reason | longtext | Yes | NULL | — | Explanation |
| status | enum('pending','approved','rejected') | No | 'pending' | INDEX | Approval status |
| crBy | bigint unsigned | Yes | NULL | — | Created by |
| appBy | bigint unsigned | Yes | NULL | — | Approved by |
| approved_at | timestamp | Yes | NULL | INDEX | Approval timestamp |
| deleted_at | timestamp | Yes | NULL | INDEX (soft delete) | Soft delete |
| created_at | timestamp | Yes | NULL | — | Laravel timestamp |
| updated_at | timestamp | Yes | NULL | — | Laravel timestamp |

### Constraints
- Unique: `(employeeId, attDate, requestType)` as `uq_attreq_emp_date_type`.

---

## 2) `new_attendance_devices` (final)

This table should keep the current ERP shape, with one integration addition: explicit `deviceSn` to map ZKTeco ADMS traffic (`zkteco_raw_logs.device_sn`) deterministically.

### Purpose
- Master list of attendance capture endpoints (Android app client devices, ZKTeco devices, future sources).
- Supports active/inactive controls and sync monitoring.

### Columns

| Column | Type | Null | Default | Key/Index | Notes |
|---|---|---|---|---|---|
| id | bigint unsigned | No | AUTO_INCREMENT | PK | Primary key |
| companyId | bigint unsigned | Yes | NULL | INDEX | Company scope |
| sectorId | bigint unsigned | Yes | NULL | INDEX | Sector scope |
| deviceCode | varchar(64) | No | — | UNIQUE | Human/business code (e.g. `ZKT-01`, `ANDROID-SELF-01`) |
| deviceSn | varchar(64) | Yes | NULL | UNIQUE, INDEX | **Add this** for direct mapping with ADMS `SN/device_sn` |
| deviceName | varchar(150) | Yes | NULL | — | Display name |
| ipAddress | varchar(64) | Yes | NULL | INDEX | Last known IP / static IP |
| port | varchar(16) | Yes | NULL | — | Service port |
| model | varchar(80) | Yes | NULL | — | Device model |
| vendor | varchar(80) | Yes | NULL | — | Vendor (ZKTeco/Android/etc.) |
| lat | decimal(10,7) | Yes | NULL | — | Physical placement latitude |
| lng | decimal(10,7) | Yes | NULL | — | Physical placement longitude |
| address | varchar(255) | Yes | NULL | — | Physical address |
| active | tinyint(1) | No | 1 | INDEX | Device enabled flag |
| lastSyncAt | timestamp | Yes | NULL | INDEX | Last heartbeat/sync time |
| crBy | bigint unsigned | Yes | NULL | — | Created by |
| appBy | bigint unsigned | Yes | NULL | — | Approved by |
| status | varchar(32) | No | 'approved' | INDEX | Workflow status |
| deleted_at | timestamp | Yes | NULL | INDEX (soft delete) | Soft delete |
| created_at | timestamp | Yes | NULL | — | Laravel timestamp |
| updated_at | timestamp | Yes | NULL | — | Laravel timestamp |

### Constraints / Composite Indexes
- Unique: `deviceCode` (existing).
- Unique: `deviceSn` (new, nullable unique).
- Index: `(sectorId, active)` as `idx_att_device_sector_active`.

---

## 3) `face_registration_android` (new final model)

This is the new canonical table for Android face registration metadata and embeddings.

### Purpose
- Stores per-employee registered face templates from Android app.
- Supports re-registration/versioning, revocation, and auditability.
- Bridges Android identity with ERP employee and optional ZKTeco user identity.

### Columns

| Column | Type | Null | Default | Key/Index | Notes |
|---|---|---|---|---|---|
| id | bigint unsigned | No | AUTO_INCREMENT | PK | Primary key |
| companyId | bigint unsigned | Yes | NULL | INDEX | Company scope |
| sectorId | bigint unsigned | Yes | NULL | INDEX | Sector scope |
| employeeId | bigint unsigned | No | — | INDEX | Owner employee |
| zktecoPin | varchar(32) | Yes | NULL | INDEX | Optional map to ZKTeco `pin` from ADMS `rtlog` |
| deviceCode | varchar(64) | Yes | NULL | INDEX | Source device code (`new_attendance_devices.deviceCode`) |
| deviceSn | varchar(64) | Yes | NULL | INDEX | Optional source SN (`new_attendance_devices.deviceSn`) |
| registrationVersion | unsigned int | No | 1 | INDEX | Increment on re-registration |
| captureCount | unsigned tinyint | No | 5 | — | Captures used in registration |
| avgEmbeddingEnc | longtext | No | — | — | Encrypted/base64 JSON of 192-d avg embedding |
| captureEmbeddingsEnc | longtext | Yes | NULL | — | Encrypted JSON array of per-capture embeddings |
| adaptiveEmbeddingsEnc | longtext | Yes | NULL | — | Encrypted JSON array of adaptive templates |
| registrationQuality | json | Yes | NULL | — | Optional quality snapshot (scores/issues/threshold profile) |
| appVersion | varchar(32) | Yes | NULL | — | Android app version at registration |
| sdkVersion | varchar(32) | Yes | NULL | — | Flutter/Dart build metadata (optional) |
| registeredAt | timestamp | Yes | NULL | INDEX | Timestamp from mobile/client event |
| lastVerifiedAt | timestamp | Yes | NULL | INDEX | Latest successful verify time |
| verifyCount | unsigned int | No | 0 | — | Number of successful verifies |
| status | enum('active','revoked','superseded') | No | 'active' | INDEX | Record lifecycle |
| isPrimary | tinyint(1) | No | 1 | INDEX | Exactly one active primary per employee |
| revokedAt | timestamp | Yes | NULL | — | Revocation time |
| revokeReason | varchar(255) | Yes | NULL | — | Revocation reason |
| crBy | bigint unsigned | Yes | NULL | — | Created by |
| appBy | bigint unsigned | Yes | NULL | — | Approved by |
| deleted_at | timestamp | Yes | NULL | INDEX (soft delete) | Soft delete |
| created_at | timestamp | Yes | NULL | — | Laravel timestamp |
| updated_at | timestamp | Yes | NULL | — | Laravel timestamp |

### Constraints / Indexes
- Unique (recommended): `(employeeId, registrationVersion)`.
- Unique (recommended for active primary): `(employeeId, isPrimary, status)` with app/service rule enforcing only one active primary.
- Index: `(companyId, sectorId, status)`.
- Index: `(employeeId, status, isPrimary)`.

---

## Integration Notes (Android + ZKTeco)

- ZKTeco ADMS lands in `zkteco_raw_logs` with `device_sn`, `query_params`, and `raw_body` from both live `rtlog` uploads and fallback `querydata` transaction snapshots.
- transaction snapshots may use `verified`, `eventtype`, `inoutstate`, `doorid`, and `time_second` instead of `verifytype`, `event`, `inoutstatus`, `eventaddr`, and explicit `time`.
- `time_second` for transaction snapshots is decoded against ZKTeco epoch `1999-07-07 00:00:00`.
- `new_attendance_devices.deviceSn` is the stable join key to connect ADMS logs to your device master.
- `face_registration_android.zktecoPin` lets one employee identity be resolved both from mobile face verification and ZKTeco pin events.
- Mobile check-in requests should write into `new_attendance_requests` with `requestType='self_punch'`, geo fields, and optional photo proof.
- ZKTeco attendance requests also write into `new_attendance_requests` with `requestType='self_punch'`, but they aggregate daily punches differently from Android: the first same-day device punch is check-in and the last same-day device punch is check-out.

---

## Minimal Laravel Migration Deltas

1. Keep existing migrations for:
   - `new_attendance_requests`
   - `new_attendance_devices`
2. Add one migration to alter `new_attendance_devices`:
   - add nullable unique `deviceSn`
3. Add one migration to create `face_registration_android` as above.

This gives a single backend contract usable by both the Android attendance app and ZKTeco ADMS ingestion flow.
