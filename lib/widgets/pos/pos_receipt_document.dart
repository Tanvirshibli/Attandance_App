import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_models.dart';

/// The POS receipt, reproduced 1:1 from the sales webapp
/// (`pphl-accounts-client/src/pages/feed-order/FeedOrderInvoice.jsx` —
/// "POS INVOICE" and "POS CHALLAN" blocks) and its 80 mm stylesheet
/// (`pos-print.scss`: 300 px wide, 8 px base, 1 px #ccc border).
///
/// The preview and the print job share this widget: printing rasterises it.
class PosReceiptDocument extends StatelessWidget {
  const PosReceiptDocument({
    super.key,
    required this.order,
    required this.docType,
  });

  static const double width = 300;
  static const Color _ink = Color(0xFF000000);

  final PosOrderDetail order;
  final PosDocType docType;

  bool get _isChallan => docType == PosDocType.challan;

  @override
  Widget build(BuildContext context) {
    final totals = order.totals;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCCCCCC)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'Roboto',
          color: _ink,
          fontSize: 12,
          height: 1.1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _logo(),
            _companyBlock(),
            _titleBlock(),
            _datesRow(),
            _salesPersonRow(),
            const _Rule(),
            if (_isChallan) ..._challanHeaderRows() else ..._invoiceHeaderRows(),
            _itemsHeader(),
            const _Rule(),
            ..._itemRows(),
            const _Rule(),
            if (_isChallan) _totalQuantityRow(totals) else _invoiceTotals(totals),
            if (!_isChallan) const _Rule(),
            _driverBlock(),
            _Rule(top: 8, bottom: 8),
            if (_isChallan) ...[
              _signatureRow(),
              _Rule(top: 8, bottom: 8),
            ],
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _logo() {
    final url = order.company.imageUrl;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: SizedBox(
          height: 80,
          child: url == null || url.isEmpty
              ? const _LogoPlaceholder()
              : Image.network(
                  url,
                  height: 80,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const _LogoPlaceholder(),
                ),
        ),
      ),
    );
  }

  Widget _companyBlock() {
    final company = order.company;
    final name = (company.nameEn?.isNotEmpty ?? false)
        ? company.nameEn!
        : 'Peoples Poultry';
    final mobile = (company.mobile?.isNotEmpty ?? false)
        ? company.mobile!
        : '01749-294031,01749-293703';
    final headOffice = (company.addressEn?.isNotEmpty ?? false)
        ? company.addressEn!
        : 'Tangail, Dhaka, Bangladesh';
    final depot = order.sector?.description ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _text(
          name,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          align: TextAlign.center,
          bottom: 4,
        ),
        _labelValueRow('Mobile: ', mobile),
        _labelValueRow('Depot: ', ' $depot'),
        _text(
          null,
          align: TextAlign.center,
          bottom: 8,
          rich: [
            const TextSpan(
              text: 'Head Office: ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: headOffice),
          ],
        ),
      ],
    );
  }

  Widget _titleBlock() {
    return _text(
      docType.receiptTitle,
      fontWeight: FontWeight.bold,
      align: TextAlign.center,
      bottom: _isChallan ? 0 : null,
    );
  }

  Widget _datesRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const Text('Inv. Date:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(_formatDate(order.invoiceDateValue)),
          const Text('~DUE Date:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(_formatDate(order.dueDateValue)),
        ],
      ),
    );
  }

  Widget _salesPersonRow() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: [
          const Text('Sales Person:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Text(order.salesPersonName ?? ''),
        ],
      ),
    );
  }

  List<Widget> _challanHeaderRows() {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _spaceBetween([
              const Text('Dealer',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Flexible(
                  child: Text(order.dealer?.displayName ?? '',
                      textAlign: TextAlign.right)),
              const Text('PH:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(order.dealer?.phone ?? ''),
            ], bottom: 4),
            const _Rule(),
            _spaceBetween([
              const Text('D Address:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Flexible(
                child: Text(
                  order.deliveryAddress ?? '',
                  textAlign: TextAlign.right,
                ),
              ),
            ], bottom: 4),
          ],
        ),
      ),
      const _Rule(),
    ];
  }

  List<Widget> _invoiceHeaderRows() {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: _spaceBetween([
          const Text('Dealer:', style: TextStyle(fontWeight: FontWeight.bold)),
          Flexible(
              child: Text(order.dealer?.displayName ?? '',
                  textAlign: TextAlign.right)),
          const Text('PH:', style: TextStyle(fontWeight: FontWeight.bold)),
          Text(order.dealer?.phone ?? ''),
        ], bottom: 4),
      ),
      const _Rule(),
      Padding(
        padding: const EdgeInsets.only(right: 16),
        child: _spaceBetween([
          const Text('Delivery:',
              style: TextStyle(fontWeight: FontWeight.bold)),
          Flexible(
            child: Text(' ${order.deliveryAddress ?? ''}',
                textAlign: TextAlign.right),
          ),
        ], bottom: 4),
      ),
      const _Rule(),
    ];
  }

  Widget _itemsHeader() {
    final columns = _isChallan
        ? const [
            (width: 5.0, label: 'SN'),
            (width: 60.0, label: 'Item'),
            (width: 35.0, label: 'Quantity'),
          ]
        : const [
            (width: 35.0, label: 'Item'),
            (width: 15.0, label: 'Price'),
            (width: 19.0, label: 'Qty'),
            (width: 18.0, label: 'Amount'),
          ];

    return Padding(
      padding: EdgeInsets.only(
        right: _isChallan ? 16 : 0,
        bottom: 4,
      ),
      child: Row(
        children: [
          for (final column in columns)
            Expanded(
              flex: column.width.toInt(),
              child: Text(
                column.label,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _itemRows() {
    if (_isChallan) {
      return [
        for (final item in order.items)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text('${item.sn}.',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 60,
                  child: Text(item.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 35,
                  child: Text(item.quantityLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ];
    }

    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 35,
                      child: Text(item.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 15,
                      child: Text(_plainNumber(item.salePrice),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 19,
                      child: Text(item.quantityLabel,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    Expanded(
                      flex: 18,
                      child: Text(item.amount.toStringAsFixed(2),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _totalQuantityRow(PosOrderTotals totals) {
    return Padding(
      padding: const EdgeInsets.only(right: 28, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total Quantity',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Flexible(
            child: Text(
              '${formatPosNumber(totals.totalBagQuantity)}Bag '
              '(${formatPosNumber(totals.totalQuantity)}Kg)',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceTotals(PosOrderTotals totals) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _totalRow('Subtotal', totals.subTotal.toStringAsFixed(2)),
          _totalRow('Transport', '${totals.transportCost.toStringAsFixed(2)}/-'),
          _totalRow('Others Cost', '${totals.othersCost.toStringAsFixed(2)}/-'),
          _totalRow(
            'VAT (${formatPosNumber(totals.vatPercent)}%)',
            '${totals.totalTax.toStringAsFixed(2)}/-',
          ),
          _totalRow(
            'Discount',
            '${totals.discountTotal.toStringAsFixed(2)}/-',
          ),
          _totalRow('Advance', '${totals.advanceAmount.toStringAsFixed(2)}/-'),
          const _Rule(),
          _totalRow('Due', '${totals.dueAmount.toStringAsFixed(2)}/-',
              bold: true),
          _totalRow('Total', '${totals.totalAmount.toStringAsFixed(2)}/-',
              bold: true, bottom: 4),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'In Words: '),
                TextSpan(text: totals.amountInWords),
              ]),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false, double bottom = 4}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.w600);
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _driverBlock() {
    final driver = order.driver;
    return Padding(
      padding: const EdgeInsets.only(right: 16, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Driver',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (driver.name != null && driver.name!.isNotEmpty)
                  Text(driver.name!,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600),
                      textAlign: TextAlign.right),
                if (driver.phone != null && driver.phone!.isNotEmpty)
                  Text(driver.phone!, textAlign: TextAlign.right),
                if (driver.address != null && driver.address!.isNotEmpty)
                  Text(driver.address!, textAlign: TextAlign.right),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signatureRow() {
    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 20),
      child: SizedBox(
        width: width * 0.95,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text('Sig: Sender',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: Text('Sig: Receiver',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _text(
          'বি. দ্র: দীর্ঘদিন সংরক্ষণের জন্য ফটোকপি করে রাখুন |',
          fontWeight: FontWeight.w600,
          align: TextAlign.center,
          bottom: 4,
        ),
        _text('Thank you for your purchase!', align: TextAlign.center),
        _text(
          'Order #${order.feedId ?? ''}',
          fontWeight: FontWeight.w600,
          align: TextAlign.center,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Center(
            child: BarcodeWidget(
              barcode: Barcode.code128(),
              data: order.feedId ?? '',
              height: 50,
              drawText: true,
              style: const TextStyle(
                fontFamily: 'Roboto',
                fontSize: 12,
                color: _ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ]),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _spaceBetween(List<Widget> children, {double bottom = 0}) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: 4),
            children[index],
          ],
        ],
      ),
    );
  }

  Widget _text(
    String? text, {
    double? fontSize,
    FontWeight? fontWeight,
    TextAlign? align,
    double? bottom,
    List<InlineSpan>? rich,
  }) {
    final style = TextStyle(fontSize: fontSize, fontWeight: fontWeight);
    final child = rich != null
        ? Text.rich(TextSpan(children: rich), textAlign: align, style: style)
        : Text(text ?? '', textAlign: align, style: style);

    return Padding(
      padding: EdgeInsets.only(bottom: bottom ?? 0, right: 16),
      child: child,
    );
  }

  static String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('d,MMMM yyyy').format(date);
  }

  static String _plainNumber(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }
}

class _Rule extends StatelessWidget {
  const _Rule({this.top = 4, this.bottom = 4});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Container(height: 1, color: const Color(0xFF000000)),
    );
  }
}

class _LogoPlaceholder extends StatelessWidget {
  const _LogoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF000000)),
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Text(
        'PPHL',
        style: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF000000),
        ),
      ),
    );
  }
}
