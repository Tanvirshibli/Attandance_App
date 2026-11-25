# POS Invoice / POS Challan printing

Approved feed orders from the sales app can be previewed and printed on a
Bluetooth POS printer from the attendance app.

Entry point: **Sales Info → POS Invoice / Challan** (`sales_info_screen.dart`).

## Flow

1. `PosOrderListScreen` — sector dropdown (from the sales API), feed category tree
   picker, date range defaulting to the last 30 days, the approved-order and
   unique-dealer counters, and one card per approved order.
2. `PosOrderDetailScreen` — order summary and items, with two actions:
   **POS Invoice** and **POS Challan**.
3. `PosReceiptPreviewScreen` — the receipt at 300 px ≈ 80 mm, with a segmented
   Invoice/Challan switch, the selected printer, and a **single** print action in
   the app bar. That one button opens the printer picker when nothing is saved;
   the in-body pill changes a saved printer.
4. `PosPrinterListScreen` — bonded classic printers and discovered BLE printers;
   tap to select (persisted), "Test" prints a small page.

## Data source

Public sales endpoints (no sales login, no JWT) documented in
`pphl_account-laravel/docs/PUBLIC_FEED_POS_API.md`:

- `GET /api/public/feed-orders/pos`
- `GET /api/public/feed-orders/pos/{id}`
- `GET /api/public/feed-order-sectors`
- `GET /api/public/feed-order-categories`

`PosService` (`lib/services/pos_service.dart`) calls them on
`AppConfig.salesApiBaseUrl`, with `sales.pos.*` keys resolved through
`EndpointConfigService` when the deployment publishes them.

## Receipt parity with the webapp

`lib/widgets/pos/pos_receipt_document.dart` reproduces
`pphl-accounts-client/src/pages/feed-order/FeedOrderInvoice.jsx` and
`src/assets/scss/utility/pos-print.scss`:

| Web | App |
| --- | --- |
| `.pos-receipt-container` 300 px / 1 px `#ccc` / 8 px base, `#000` on `#fff` | `PosReceiptDocument.width = 300`, same colours |
| Logo 80 px, company name 20 px bold, Mobile/Depot/Head Office 12 px | same |
| Titles `~~ Sales Invoice ~~` / `~~Delivery Challan ~~` | `PosDocType.receiptTitle` |
| `Inv.`/`~DUE` dates `D,MMMM YYYY` | `DateFormat('d,MMMM yyyy')` |
| Dealer line `tradeName (dealerCode) zoneName` + `PH:` | `PosDealer.displayName` |
| Challan columns SN 5 % / Item 60 % / Quantity 35 % | same flex weights |
| Invoice columns Item 35 % / Price 15 % / Qty 19 % / Amount 18 % | same |
| Challan `Total Quantity {bag}Bag ({qty}Kg)` | same |
| Invoice subtotal/transport/others/VAT/discount/advance/due/total + In Words | same, `toStringAsFixed(2)` and `/-` suffixes |
| `Driver`, `Sig: Sender` / `Sig: Receiver` (challan only), Bangla note, `Order #feedId`, Code128 barcode | same |

Deliberate deviation: the webapp's invoice quantity cell contains a typo
(`${bagQty}11 Bag (${qty}1 Kg)`); the app prints `2 Bag (100 Kg)`.

Because the preview widget *is* the print source, preview and paper cannot
diverge.

## Printing pipeline

- `RepaintBoundary` around the receipt → `toImage(pixelRatio: 2)` → PNG.
- `buildPngReceiptCommands` (`lib/services/esc_pos_builder.dart`) resizes the PNG
  to the printer width (384 dots for 58 mm, 576 for 80 mm), rasterises it with
  `esc_pos_utils_plus` (`GS v 0`), then feeds 3 lines and issues a partial cut.
- `PosPrinterService` sends the bytes in chunks: BLE via `flutter_blue_plus`
  (writable characteristic, 180-byte chunks) or classic SPP via
  `print_bluetooth_thermal` (400-byte chunks).
- The selected printer is stored in SharedPreferences (`pos_printer_saved`) and
  reused on the next preview.

## Android permissions

Declared in `android/app/src/main/AndroidManifest.xml`:

- `BLUETOOTH_SCAN` (`neverForLocation`), `BLUETOOTH_CONNECT` (API 31+)
- `BLUETOOTH`, `BLUETOOTH_ADMIN` with `maxSdkVersion="30"`

The app requests the runtime permissions before scanning/printing and shows an
actionable message when they are permanently denied. Pair classic printers in
Android Bluetooth settings first.

## Tests

```
flutter analyze lib/screens/pos lib/services lib/widgets/pos lib/models/pos_models.dart
flutter test test/pos_models_test.dart test/pos_receipt_document_test.dart test/pos_escpos_test.dart
```

`pos_models_test` covers the JSON contract and receipt labels;
`pos_receipt_document_test` pins the field order for both documents and the
300 px width; `pos_escpos_test` checks the raster header width for 384/576 dots
and the cut sequence.

## Beta OTA

`POS printing` ships on the **beta** channel only until it is promoted:

```
scripts\build-production-apk.ps1 -Channel beta -Publish -UpdateLevel Minor -ReleaseNotes "POS Invoice / Challan printing"
```

Keep the build number monotonic inside the 9000+ beta band: bump `pubspec.yaml`
to the last published beta code *before* running the script (the script only
raises the number into the band, it does not jump above an existing beta code).
