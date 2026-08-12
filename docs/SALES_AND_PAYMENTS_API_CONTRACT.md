# Sales & Payments API Contract (Android Attandance_App)

**Last updated:** July 28, 2026  
**Audience:** External sales backend team · pphl_erp (HRM) · ZKTeco Mobile App API admins  
**App:** `Attandance_App` (Flutter)  
**Status:** **Sales Info reporting and Post Sale create are live** against `https://sales.peoplesitsolution.online` when `USE_SALES_DEMO_DATA=false` (default). **Auth-wise payment POST** is live when `payment.enabled` is on. HRM loan/payslip screens still demo by default (`USE_PAYMENT_DEMO_DATA=true`).

---

## Demo → live switch (app)


| Module   | Compile-time flag                           | Default        | Live requirement                                      |
| -------- | ------------------------------------------- | -------------- | ----------------------------------------------------- |
| Sales reporting | `--dart-define=USE_SALES_DEMO_DATA=true` | `false` (live) | Person-sales GET + HRM eligibility list               |
| Sales create (Post sale) | `--dart-define=USE_SALES_DEMO_DATA=true` | `false` (live) | `POST /api/sales-person-sales` (egg, fertilizer, liveBird, cullBird) or `POST /api/booking-person-books` (feed, chicks) |
| Payments | `--dart-define=USE_PAYMENT_DEMO_DATA=false` | `true` (demo)  | Existing pphl_erp JWT APIs + ZKTeco `payment.enabled` |


Sales reporting base URL (override): `--dart-define=SALES_API_BASE_URL=http://host:port`  
Default: `https://sales.peoplesitsolution.online`

ZKTeco dashboard (**Settings → Mobile App API**) can override endpoint URLs and feature flags without an app rebuild:

- `feature.sales.enabled` (**must be on** for Sales Info; when off the app shows a disabled-module empty state and does not call person-sales)
- `feature.payment.enabled` / app `payment.enabled` (**must be on** for auth-wise Payments report; aliases accepted)
- Endpoint keys listed below (including `sales.personSales`, `sales.allDealers`, `payment.authWise`, `payment.setupData`)

**Canonical employee id:** always numeric `employees.id` from HRM `GET /api/v1/get-my-info` (`user.employeeId` / app `canonicalEmployeeId`). **Do not** use display `emp_id` strings.

**Auth header (HRM / Payments only):**

```http
Authorization: Bearer <hrm_jwt>
Accept: application/json
```

Person-sales reporting uses **no Authorization header**.

---



## Part A — Sales (live person-sales + demo Post Sale)

HRM eligibility gate (JWT):

- `GET /api/get-sales-employee-list` → `{ "data": [ { "employeeId", "employeeName", ... } ] }`  
  Employee must appear in this list to open Sales Info when reporting is live.

### A.1 Salesperson sales report (live)

`GET {SALES_API_BASE_URL}/api/sales-person-sales/{employeeId}?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD`

**Rules**

- **No auth** — open GET with path `employeeId` = logged-in `canonicalEmployeeId`.
- Query: `from_date`, `to_date` (`YYYY-MM-DD`). App presets: This month / Last month / Custom.
- App config key: `sales.personSales` → base path without trailing id (app appends `/{employeeId}`).

**Success response (shape)**

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "employee": {
      "input_id": 27,
      "matched_by": "employeeId",
      "id": 20,
      "employee_id": 27,
      "employee_name": "Example Name"
    },
    "filters": {
      "from_date": "2026-01-01",
      "to_date": "2026-07-31",
      "status_rules": {
        "egg": "approved",
        "feed": "approved",
        "fertilizer": "approved",
        "chicks": "approved",
        "liveBird": "delivered",
        "cullBird": "delivered"
      }
    },
    "overall": {
      "total_orders": 10,
      "total_returns": 1,
      "total_details": 40,
      "gross_sales": 500000,
      "sales_return": 10000,
      "net_sales": 490000,
      "invoice_net_total": 490000,
      "quantity_by_unit": [
        {
          "unit_id": 1,
          "unit_name": "kg",
          "gross_qty": 450,
          "return_qty": 0,
          "net_qty": 450
        },
        {
          "unit_id": null,
          "unit_name": "pcs",
          "gross_qty": 54480,
          "return_qty": 0,
          "net_qty": 54480
        }
      ]
    },
    "egg": {
      "data": [],
      "summary": {},
      "products": [],
      "dealers": [],
      "sectors": [],
      "integrity": {}
    },
    "feed": {
      "data": [],
      "summary": {},
      "products": [],
      "dealers": [],
      "sectors": [],
      "integrity": {}
    },
    "fertilizer": { "data": [], "summary": {}, "products": [], "dealers": [], "sectors": [], "integrity": {} },
    "chicks": { "data": [], "summary": {}, "products": [], "dealers": [], "sectors": [], "integrity": {} },
    "liveBird": { "data": [], "summary": {}, "products": [], "dealers": [], "sectors": [], "integrity": {} },
    "cullBird": { "data": [], "summary": {}, "products": [], "dealers": [], "sectors": [], "integrity": {} }
  }
}
```

App parsers also accept legacy camelCase employee keys and module `details[]` (alias of `data[]`).

**Module blocks** (`egg`, `feed`, `fertilizer`, `chicks`, `liveBird`, `cullBird`):

| Section | Fields used by app |
| ------- | ------------------ |
| `summary` | `total_orders`, `total_returns`, `net_sales`, `gross_sales`, `net_qty`, … |
| `products[]` | `name`, `net_amount`, `net_qty`, `unit_name`, optional `package_size` |
| `dealers[]` / `sectors[]` | `name`, `net_amount`, `net_qty` |
| `data[]` (line details; legacy `details[]` also accepted) | `reference_no`, `invoice_date`, `type`, `status`, `dealer_name`, `product_name`, `qty`, `line_amount`, `unit_name` |
| `overall.quantity_by_unit[]` | Per-unit net qty chips in the Overall strip |
| `integrity` / `status_rules` | Ignored by UI for now |

Android UI: overall KPI strip (orders, returns, sales, qty-by-unit) → module tabs → summary + expandable Products / Dealers / Sectors / Line details.

### A.2 Create sale (Post Sale) — live (non feed / non chicks)

Applies to modules **egg**, **fertilizer**, **liveBird**, **cullBird** only. **Feed** and **chicks** use [A.2b Booking create](#a2b-booking-create-feed--chicks--live).

`POST {SALES_API_BASE_URL}/api/sales-person-sales`

**Content-Type:** `multipart/form-data` (same field names as Postman form-data).

| Field | Example |
| ----- | ------- |
| `module` | `feed` |
| `salesPersonId` | `27` |
| `dealerId` | `235` |
| `salesPointId` | `28` |
| `companyId` | `2` |
| `totalAmount` | `5900` |
| `invoiceDate` / `dueDate` | `YYYY-MM-DD` |
| `saleType` | `Cash` |
| `details[0][productId]` | `45` |
| `details[0][tradePrice]` | `2850` |
| `details[0][salePrice]` | `2950` |
| `details[0][qty]` | `100` |
| `details[0][unitId]` | `1` |
| `details[0][unitBatchNo]` | optional |

**Success:**

```json
{
  "success": true,
  "message": "Sales person order created successfully.",
  "data": {
    "module": "feed",
    "id": 4057,
    "reference_no": "CFO26074057",
    "status": "pending",
    "salesPerson": 27,
    "totalAmount": 5900
  }
}
```

App config key: `sales.create` (POST, full URL or path).

When `USE_SALES_DEMO_DATA=true`, Post Sale stays on-device demo only.

### A.2b Booking create (feed & chicks) — live

`POST {SALES_API_BASE_URL}/api/booking-person-books`

**Content-Type:** `multipart/form-data` (field names match Postman form-data).

| Field | Notes |
| ----- | ----- |
| `module` | `feed` or `chicks` |
| `dealerId`, `categoryId`, `subCategoryId`, `childCategoryId`, `bookingPointId` | IDs |
| `bookingPerson` | App sends logged-in `canonicalEmployeeId` |
| `bookingType` | e.g. `regular` |
| `isBookingMoney` | `0` / `1` |
| `discount`, `discountType` | e.g. `fixed` |
| `advanceAmount`, `totalAmount` | numbers |
| `bookingDate`, `invoiceDate` | `YYYY-MM-DD` |
| `note` | optional header note |
| `details[i][productId]`, `unitId`, `qty`, `price`, `note` | line item |
| **Chicks only** | `cZoneId`, `isMultiDelivery` (`0`/`1`), optional `chicksPriceId`; line `cdPriceId`, `mrp`, `details[i][settingIds][j]`, `details[i][flockIds][j]` |
| **Optional** | `commissionId` |

**Success (example):**

```json
{
  "success": true,
  "message": "Booking created successfully.",
  "data": {
    "module": "chicks",
    "id": 123,
    "bookingNo": "BK26070123",
    "status": "pending",
    "totalAmount": 5900
  }
}
```

App config key: `sales.booking.create` (POST, full URL or path).

### A.3 Errors

```json
{ "success": false, "message": "Human readable error" }
```

### A.4 App config keys


| Key                 | Method | Path / notes |
| ------------------- | ------ | ------------ |
| `sales.eligibility` | GET    | HRM `/api/get-sales-employee-list` |
| `sales.personSales` | GET    | `{salesBase}/api/sales-person-sales` (app appends `/{id}`) |
| `sales.overview` / `sales.list` | GET | Legacy aliases → same person-sales base (unused by UI) |
| `sales.create`      | POST   | `{salesBase}/api/sales-person-sales` (form-data; non feed/chicks) |
| `sales.booking.create` | POST | `{salesBase}/api/booking-person-books` (form-data; feed & chicks) |

Enable `feature.sales.enabled` (default true in app fallback).

---



## Part B — Payments (pphl_erp — **consume existing APIs; no backend changes**)

All routes are under JWT `middleware: jwt.verify`, prefix `/api/v1`.  
Android screens map 1:1 to these resources. Field names match Laravel `*Resource` classes.

### B.1 Screen → endpoint map


| Android screen           | Method | Path                              | Query / body                            |
| ------------------------ | ------ | --------------------------------- | --------------------------------------- |
| Payslip list             | GET    | `/api/v1/payroll`                 | `employeeId`, optional `month`, `limit` |
| Payslip detail           | GET    | `/api/v1/payroll/{id}`            | — (bare `PayrollResource` or wrapped)   |
| My loans                 | GET    | `/api/v1/loans-employee`          | `employeeId`                            |
| Loan detail              | GET    | `/api/v1/loan/{id}`               | —                                       |
| Loan payment history     | GET    | `/api/v1/get/pay-loan`            | `employeeId`                            |
| Post loan payment        | POST   | `/api/v1/pay-loan/store`          | see below                               |
| Provident fund (current) | GET    | `/api/v1/providentfunds-employee` | `employeeId`                            |
| Provident fund history   | GET    | `/api/v1/providentfunds`          | `employeeId`                            |
| Mess deposit             | GET    | `/api/v1/mess-deposit-employee`   | `employeeId`                            |
| Compensation             | GET    | `/api/v1/facility-employee`       | `employeeId`                            |




### B.2 Payroll / payslip (`PayrollResource`)

**List**

```json
{
  "message": "Success!",
  "data": [ { /* PayrollResource */ } ],
  "meta": { "current_page": 1, "last_page": 1, "per_page": 100, "total": 12 }
}
```

**Key fields the app displays**


| Field                                                                                                                          | UI                                                                       |
| ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `month`                                                                                                                        | Display string e.g. `"June 2026"` (list filter may use DB `Y-n` / `Y-m`) |
| `basics`, `houses`, `medicals`, `foods`, `sGross`                                                                              | Earnings                                                                 |
| `mess`, `absenceDeduction`, `providentFund`, `loan`, `messDeposit`, `tax`, `serviceBill`, `punishment`, `others`, `adjustment` | Deductions                                                               |
| `presentDays`, `absentDays`, `holidays`, `leaves`                                                                              | Attendance                                                               |
| `netSalary`, `netPay`, `netReceivable`                                                                                         | Net figures (prefer `netReceivable` for headline)                        |
| `paymentMethod`, `status`, `designation`                                                                                       | Meta                                                                     |
| `sector.name`                                                                                                                  | Sector label                                                             |




### B.3 Loans (`LoanResource`)

**Preferred list:** `GET /api/v1/loans-employee?employeeId=` → `{ "message": "Success!", "data": [ ... ] }`  
Statuses typically `approved` / `ongoing`.


| Field                                                                                   | Notes                                                   |
| --------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| `id`                                                                                    | Numeric PK — use this as `loanId` when posting payments |
| `loanId`                                                                                | Display code e.g. `lon-012`                             |
| `amount`, `installmentAmount`, `installmentCount`, `deadlineDate`, `loanType`, `status` | Detail UI                                               |




### B.4 Loan payments (`LoanPaymentResource`)

**List:** `GET /api/v1/get/pay-loan?employeeId=`


| Field                                                          | Notes                 |
| -------------------------------------------------------------- | --------------------- |
| `amount`, `amountPaidSoFar`, `paymentMethod`, `date`, `status` | History rows          |
| `loan`                                                         | Nested `LoanResource` |


**Create:** `POST /api/v1/pay-loan/store`

```json
{
  "employeeId": 45,
  "loanId": 12,
  "amount": 5000,
  "date": "2026-07-16",
  "paymentMethod": "Cash"
}
```

Note: `loanId` is numeric `loans.id`, not `lon-012`.

### B.5 Provident fund

`GET /api/v1/providentfunds-employee?employeeId=` → `{ "message", "data": { ... } }`  
Fields used: `openingBalance`, `monthlyPfAmount`, `pfAmountTotal`, `pfInterestTotal`, `closingBalance`, `closingBalanceWithProfit`, `month`, `status`.

### B.6 Mess deposit

`GET /api/v1/mess-deposit-employee?employeeId=`  
Fields: `messDepositId`, `dAmount`, `totalDepAmount`, `tType`, `tDate`, `note`, `status`, `department`.

### B.7 Compensation / facility

`GET /api/v1/facility-employee?employeeId=`  
Fields: `basics`, `houses`, `medicals`, `foods`, `sGross`, `mobileBill`, `mess`, `quarter`, `serviceBill`, `loanF`, `tax`, `paymentMethod`, nested designation/department/sector, `jDate`.

### B.8 App config keys (ZKTeco)


| Key                      | Method | Path                                 |
| ------------------------ | ------ | ------------------------------------ |
| `payment.loans`          | GET    | `/api/v1/loans-employee`             |
| `payment.loan.detail`    | GET    | `/api/v1/loan` (+ `/{id}` in app)    |
| `payment.post`           | POST   | `/api/v1/pay-loan/store`             |
| `payment.history`        | GET    | `/api/v1/get/pay-loan`               |
| `payment.payroll`        | GET    | `/api/v1/payroll`                    |
| `payment.payroll.detail` | GET    | `/api/v1/payroll` (+ `/{id}` in app) |
| `payment.pf`             | GET    | `/api/v1/providentfunds-employee`    |
| `payment.pf.history`     | GET    | `/api/v1/providentfunds`             |
| `payment.mess`           | GET    | `/api/v1/mess-deposit-employee`      |
| `payment.facility`       | GET    | `/api/v1/facility-employee`          |


Enable `feature.payment.enabled` for the live auth-wise Payments report (HRM payslip/loan demo still uses `USE_PAYMENT_DEMO_DATA`).

### B.9 Important HRM quirks (no backend change required)

1. Employee scoping is **query-parameter based** — mobile must always pass the logged-in `employees.id`.
2. Payroll `month` in filters ≠ display `F Y` in `PayrollResource`.
3. Dual `loanId` meaning: string code on loan vs numeric FK on payments.
4. Do **not** use admin-only routes from the employee app: `payroll-generate`, `approve-payroll`, loan create/status, contractual ledger, `employeewiseLoanPayment` (broken).

---

## Part C — Auth-wise payment receive (live on Payments page)

`GET {SALES_API_BASE_URL}/api/auth-wise-payments/{employeeId}?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD`

**Rules**

- **No auth** — open GET; path id = logged-in `canonicalEmployeeId`.
- Same host default as Sales: `https://sales.peoplesitsolution.online`.
- App config key: `payment.authWise` (base path without trailing id).
- Feature gate: ZKTeco `feature.payment.enabled` / app `payment.enabled` (**must be on**).
- App pre-check: `GET /api/payment-setup-data` — logged-in `canonicalEmployeeId` must appear in `employeeList[].employeeId` before calling the report.
- **200 with zero payments** is success (empty period), not an error.

**HTTP 422 (common)**

App parsing: prefer JSON **`error`** over generic **`message`** for user-visible headline; show mapped English action hint as secondary line.

| `error` / message | Meaning | Fix |
| ----------------- | ------- | --- |
| `Sales employee was not found.` | Path `employeeId` not in sales employee flat table | Sales admin: create/link employee record |
| Bengali: *এই employee-এর সাথে কোনো user account পাওয়া যায়নি* (no user account linked) | Employee is in `employeeList` but has no sales `userId` (e.g. GAZI `employeeId` **1904** vs working Shuntu **19** with `userId: 14`) | Sales admin: link a user account to that employee on the sales server |
| App shows friendly text | *Your sales account is not linked. Contact admin.* | Same backend fix |

Verified 2026-08-11: `GET .../auth-wise-payments/19` → **200**; `GET .../auth-wise-payments/1904` → **422** (no linked user account).

**Success shape (summary)**

```json
{
  "success": true,
  "message": "...",
  "data": {
    "employee": { "id": 14, "employeeId": 19, "employeeName": "..." },
    "filters": { "from_date": "2026-07-01", "to_date": "2026-07-27" },
    "overall": {
      "total_payments": 1,
      "total_amount": 2500,
      "total_dealers": 1,
      "total_companies": 1,
      "module_totals": { "chicks": { "total_payments": 1, "total_amount": 2500 } }
    },
    "egg": { "data": [], "summary": {}, "dealers": [], "companies": [], "payment_methods": [] },
    "chicks": {
      "data": [{ "id": 27917, "voucher_no": "...", "amount": 2500, "dealer_name": "...", "module": "chicks" }],
      "summary": { "total_payments": 1, "total_amount": 2500 },
      "dealers": [],
      "companies": [],
      "payment_methods": []
    }
  }
}
```

Modules: `egg`, `feed`, `fertilizer`, `chicks`, `liveBird`, `cullBird`, `unclassified`.

HRM payslip/loan/PF screens are under **Services → HR Benefits** (`HrBenefitsHubScreen`) and still default to demo (`USE_PAYMENT_DEMO_DATA`).

### C.1 Create auth-wise payment (Post receive)

`POST {SALES_API_BASE_URL}/api/auth-wise-payments`

**Content-Type:** `multipart/form-data`.

| Field | Example |
| ----- | ------- |
| `employeeId` | `27` |
| `payments[0][companyId]` | `3` |
| `payments[0][recType]` | `1` |
| `payments[0][receiverId]` | `235` (auth-wise receiver — use **`employeeList[].id`**, not `employeeId`) |
| `payments[0][amount]` | `1000` |
| `payments[0][recDate]` | `YYYY-MM-DD` |
| `payments[0][paymentType]` | payment type id from setup (`paymentTypeList[].id`) |
| `payments[0][paymentMode]` | bank id from setup (`bankList[].id`) |
| `payments[0][paymentFor]` | `2` |
| `payments[0][invoiceType]` | `2` |
| `payments[0][note]` | optional |
| `payments[0][trxId]` | optional |
| `payments[0][ref]` | optional |

App config key: `payment.authWisePost` (POST; falls back to `payment.authWise` URL).

**Success:** `success`, `message`, `data.createdPaymentCount`, `data.payments[].voucherNo`.

### C.2 Payment setup data (Post receive dropdowns)

`GET {SALES_API_BASE_URL}/api/payment-setup-data` — **no auth**.

App config key: `payment.setupData`.

**Success shape:**

```json
{
  "success": true,
  "data": {
    "bankList": [{ "id": 65, "bankName": "...", "shortName": "...", "company": { "id": 3, "nameEn": "..." } }],
    "employeeList": [{ "id": 235, "employeeId": 110, "employeeName": "..." }],
    "paymentTypeList": [{ "id": 1, "name": "Feed" }]
  }
}
```

**App mapping:** Bank → `paymentMode` + auto `companyId` from `company.id`; Receiver → `receiverId` = `employeeList[].id`; Payment type → `paymentType`.

### C.3 All dealer lists (Post sale dropdown)

`GET {SALES_API_BASE_URL}/api/all-dealer-lists` — **no auth**.

App config key: `sales.allDealers`.

**Success shape:** `data.eggDealList`, `feedDealList`, `fertilizerDealList`, `liveBirdDealList`, `wastageDealList` — each item includes `id`, `tradeName`, `dealerCode`, `zoneName`, etc.

**Module → list (app):** `feed` → feed; `egg` → egg; `fertilizer` → fertilizer; `liveBird` / `chicks` / `cullBird` → liveBird (temporary). Post sale uses selected dealer `id` as `dealerId`.

---

## Checklist for dependency teams



### Sales backend team

- [ ] Implement overview / list / create with employee-only scoping  
- [ ] Align JSON field names with Part A  
- [ ] Accept HRM JWT (or document alternate auth for app wiring)  
- [x] Sales Info live person-sales GET wired (`USE_SALES_DEMO_DATA` default `false`)
- [ ] Implement live Post Sale create API; then remove demo create store
- [ ] Optionally register `sales.personSales` in ZKTeco dashboard if overriding default host  



### HRM / ZKTeco admins (payments)

- [ ] Confirm JWT employee can call the Part B GETs with their `employeeId`  
- [ ] In ZKTeco **Mobile App API**, set HRM base URL and enable `payment.enabled`  
- [ ] Register payment.* endpoint rows if not seeded  
- [ ] Notify Android to set `USE_PAYMENT_DEMO_DATA=false`  

---



## Related app docs

- [MOBILE_EMPLOYEE_FEATURES.md](MOBILE_EMPLOYEE_FEATURES.md)  
- [AUTHENTICATION_INTEGRATION.md](AUTHENTICATION_INTEGRATION.md)  
- [TUNNEL_DEVELOPMENT.md](TUNNEL_DEVELOPMENT.md)  
- [EMULATOR_TESTING.md](EMULATOR_TESTING.md)

