# Sales & Payments API Contract (Android Attandance_App)

**Last updated:** July 16, 2026  
**Audience:** External sales backend team · pphl_erp (HRM) · ZKTeco Mobile App API admins  
**App:** `Attandance_App` (Flutter)  
**Status:** App UI ships with **demo data** by default. Flip to live with dart-defines + endpoint config.

---

## Demo → live switch (app)


| Module   | Compile-time flag                           | Default       | Live requirement                                      |
| -------- | ------------------------------------------- | ------------- | ----------------------------------------------------- |
| Sales    | `--dart-define=USE_SALES_DEMO_DATA=false`   | `true` (demo) | External sales APIs + eligibility list                |
| Payments | `--dart-define=USE_PAYMENT_DEMO_DATA=false` | `true` (demo) | Existing pphl_erp JWT APIs + ZKTeco `payment.enabled` |


ZKTeco dashboard (**Settings → Mobile App API**) can override endpoint URLs and feature flags without an app rebuild:

- `feature.sales.enabled`
- `feature.payment.enabled`
- Endpoint keys listed below

**Canonical employee id:** always numeric `employees.id` from HRM `GET /api/v1/get-my-info` (`user.employeeId` / app `canonicalEmployeeId`). **Do not** use display `emp_id` strings.

**Auth header (all authenticated calls):**

```http
Authorization: Bearer <hrm_jwt>
Accept: application/json
```

---



## Part A — Sales (external sales project — **new APIs to implement**)

HRM already exposes eligibility only:

- `GET /api/get-sales-employee-list` → `{ "data": [ { "employeeId", "employeeName", ... } ] }`

The Android app expects the **sales product backend** (or a BFF) to provide the following. Suggested paths (configurable via ZKTeco app-config keys `sales.overview`, `sales.list`, `sales.create`):

Base suggestion: same host the app already trusts, or a dedicated sales base registered in Mobile App API.

### A.1 Personal overview

`GET /api/v1/mobile/sales/overview?employeeId={id}&period={this_month|last_month|custom}`

**Rules**

- Return KPIs for **that employee only** (no company-wide totals).
- Period values: `this_month`, `last_month`, `custom` (custom may later accept `from`/`to`; for v1 returning last 90 days is fine).

**Success response**

```json
{
  "message": "Success",
  "data": {
    "period": "this_month",
    "targetAmount": 150000,
    "achievedAmount": 77500,
    "ordersCount": 12,
    "revenue": 77500,
    "conversionRate": 54.5,
    "visitsCount": 22
  }
}
```


| Field            | Type    | Notes                                     |
| ---------------- | ------- | ----------------------------------------- |
| `period`         | string  | Echo of requested period or display label |
| `targetAmount`   | number  | Personal monthly target                   |
| `achievedAmount` | number  | Personal achieved toward target           |
| `ordersCount`    | integer | Count of own sale postings / orders       |
| `revenue`        | number  | Sum of own sale amounts in period         |
| `conversionRate` | number  | Percent 0–100                             |
| `visitsCount`    | integer | null                                      |




### A.2 Own sale postings list

`GET /api/v1/mobile/sales/postings?employeeId={id}&from=YYYY-MM-DD&to=YYYY-MM-DD`

**Rules**

- **Must filter server-side** to `employeeId` only. Never return other employees’ sales.
- `from` / `to` optional; default current month.

**Success response**

```json
{
  "message": "Success",
  "data": [
    {
      "id": 1001,
      "employeeId": 45,
      "saleDate": "2026-07-14",
      "amount": 18500,
      "customerName": "Green Valley Outlet",
      "productName": "Layer Feed 50kg",
      "quantity": 40,
      "notes": "Monthly restock",
      "status": "approved"
    }
  ]
}
```


| Field          | Type                | Required                          |
| -------------- | ------------------- | --------------------------------- |
| `id`           | integer             | yes                               |
| `employeeId`   | integer             | yes                               |
| `saleDate`     | string `YYYY-MM-DD` | yes                               |
| `amount`       | number              | yes                               |
| `customerName` | string              | yes (alias `outletName` accepted) |
| `productName`  | string              | no                                |
| `quantity`     | number              | no                                |
| `notes`        | string              | no                                |
| `status`       | string              | yes — `submitted`                 |




### A.3 Create sale (salesperson posts own sale)

`POST /api/v1/mobile/sales/postings`

**Request body**

```json
{
  "employeeId": 45,
  "saleDate": "2026-07-16",
  "amount": 12500,
  "customerName": "Sunrise Agro Store",
  "productName": "Broiler Starter",
  "quantity": 10,
  "notes": "Optional note"
}
```

**Rules**

- Persist against authenticated employee; reject if body `employeeId` ≠ JWT employee (recommended).
- New rows should start as `submitted` (or `approved` if your workflow auto-approves).

**Success response**

```json
{
  "message": "Sale submitted successfully",
  "data": {
    "id": 1101,
    "employeeId": 45,
    "saleDate": "2026-07-16",
    "amount": 12500,
    "customerName": "Sunrise Agro Store",
    "productName": "Broiler Starter",
    "quantity": 10,
    "notes": "Optional note",
    "status": "submitted"
  }
}
```



### A.4 Errors

```json
{ "message": "Human readable error" }
```

HTTP: `400` validation, `401` auth, `403` not a sales user / wrong employee, `404` not found, `500` server.

### A.5 App config keys (ZKTeco Mobile App API)


| Key                 | Method | Suggested path                                        |
| ------------------- | ------ | ----------------------------------------------------- |
| `sales.eligibility` | GET    | `/api/get-sales-employee-list` (HRM — already exists) |
| `sales.overview`    | GET    | `/api/v1/mobile/sales/overview`                       |
| `sales.list`        | GET    | `/api/v1/mobile/sales/postings`                       |
| `sales.create`      | POST   | `/api/v1/mobile/sales/postings`                       |


Enable `feature.sales.enabled` when live.

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
- [ ] Notify Android to set `USE_SALES_DEMO_DATA=false` and register endpoints in ZKTeco dashboard  



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

