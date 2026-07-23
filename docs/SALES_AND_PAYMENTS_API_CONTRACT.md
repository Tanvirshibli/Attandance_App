# Sales & Payments API Contract (Android Attandance_App)

**Last updated:** July 23, 2026  
**Audience:** External sales backend team · pphl_erp (HRM) · ZKTeco Mobile App API admins  
**App:** `Attandance_App` (Flutter)  
**Status:** **Sales Info reporting is live** against the person-sales API (no auth). **Post Sale** remains device demo until a create API exists. Payments still demo by default.

---

## Demo → live switch (app)


| Module   | Compile-time flag                           | Default        | Live requirement                                      |
| -------- | ------------------------------------------- | -------------- | ----------------------------------------------------- |
| Sales reporting | `--dart-define=USE_SALES_DEMO_DATA=true` | `false` (live) | Person-sales GET + HRM eligibility list               |
| Sales create (Post sale) | — (always demo for now) | demo store | Future create endpoint                                |
| Payments | `--dart-define=USE_PAYMENT_DEMO_DATA=false` | `true` (demo)  | Existing pphl_erp JWT APIs + ZKTeco `payment.enabled` |


Sales reporting base URL (override): `--dart-define=SALES_API_BASE_URL=http://host:port`  
Default: `http://43.224.116.185:8001`

ZKTeco dashboard (**Settings → Mobile App API**) can override endpoint URLs and feature flags without an app rebuild:

- `feature.sales.enabled` (fallback default `true`)
- `feature.payment.enabled`
- Endpoint keys listed below

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

### A.2 Create sale (Post Sale) — still demo

There is **no live create endpoint** yet. The app keeps **Post sale** UI and stores submissions in an in-memory demo list for the session.

Future target (when available):

`POST /api/v1/mobile/sales/postings` with body `{ employeeId, saleDate, amount, customerName, productName?, quantity?, notes? }`.

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
| `sales.create`      | POST   | Reserved; Post Sale still demo |

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


Enable `feature.payment.enabled` when going live (optional gate; demo mode ignores it).

### B.9 Important HRM quirks (no backend change required)

1. Employee scoping is **query-parameter based** — mobile must always pass the logged-in `employees.id`.
2. Payroll `month` in filters ≠ display `F Y` in `PayrollResource`.
3. Dual `loanId` meaning: string code on loan vs numeric FK on payments.
4. Do **not** use admin-only routes from the employee app: `payroll-generate`, `approve-payroll`, loan create/status, contractual ledger, `employeewiseLoanPayment` (broken).

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

