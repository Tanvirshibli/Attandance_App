import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/pos_models.dart';
import '../../services/pos_printer_service.dart';
import '../../services/pos_service.dart';
import '../../widgets/pos/pos_receipt_document.dart';
import '../../widgets/ui/ui.dart';
import 'pos_printer_list_screen.dart';

/// Shows the POS receipt exactly as it will be printed, and prints it to the
/// selected Bluetooth POS printer.
class PosReceiptPreviewScreen extends StatefulWidget {
  const PosReceiptPreviewScreen({
    super.key,
    required this.orderId,
    required this.docType,
  });

  final int orderId;
  final PosDocType docType;

  @override
  State<PosReceiptPreviewScreen> createState() => _PosReceiptPreviewScreenState();
}

class _PosReceiptPreviewScreenState extends State<PosReceiptPreviewScreen> {
  static const int _dotsPerLine = 576;

  final PosService _service = PosService();
  final PosPrinterService _printerService = PosPrinterService.instance;
  final GlobalKey _receiptKey = GlobalKey();

  late PosDocType _docType = widget.docType;
  PosOrderDetail? _order;
  PosPrinterDevice? _printer;
  bool _isLoading = true;
  bool _isPrinting = false;
  String? _error;
  double _printProgress = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final orderResult = await _service.getOrder(widget.orderId);
    final printer = await _printerService.getSavedPrinter();
    if (!mounted) return;

    setState(() {
      _printer = printer;
      _order = orderResult.success ? orderResult.data : null;
      _error = orderResult.success
          ? null
          : (orderResult.message ?? 'Could not load the order.');
      _isLoading = false;
    });
  }

  Future<void> _choosePrinter() async {
    final device = await Navigator.push<PosPrinterDevice>(
      context,
      MaterialPageRoute(builder: (_) => const PosPrinterListScreen()),
    );
    if (!mounted || device == null) return;
    setState(() => _printer = device);
  }

  Future<Uint8List?> _captureReceipt() async {
    final boundary =
        _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _print() async {
    if (_isPrinting) return;

    final order = _order;
    if (order == null) return;

    var printer = _printer;
    if (printer == null) {
      await _choosePrinter();
      if (!mounted) return;
      printer = _printer;
    }

    if (printer == null) {
      _showMessage('Select a Bluetooth printer first.');
      return;
    }

    setState(() {
      _isPrinting = true;
      _printProgress = 0;
    });

    try {
      final bytes = await _captureReceipt();
      if (bytes == null) {
        throw PosPrinterException('Could not render the receipt.');
      }

      await _printerService.printPng(
        bytes,
        printer: printer,
        dotsPerLine: _dotsPerLine,
        onProgress: (sent, total) {
          if (!mounted || total == 0) return;
          setState(() => _printProgress = sent / total);
        },
      );

      if (!mounted) return;
      _showMessage('Sent to ${printer.name}.');
    } on PosPrinterException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (error) {
      if (mounted) _showMessage('Printing failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _printProgress = 0;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(_docType.label),
        actions: [
          IconButton(
            tooltip: 'Select printer',
            onPressed: _choosePrinter,
            icon: Icon(PhosphorIconsDuotone.printer),
          ),
          IconButton(
            tooltip: 'Print',
            onPressed: _isPrinting ? null : _print,
            icon: _isPrinting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(PhosphorIconsDuotone.printer),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: AppEmptyState(
                      icon: AppIcons.error,
                      title: 'Could not load the order',
                      subtitle: _error!,
                      onRetry: _load,
                    ),
                  ),
                )
              : order == null
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        _toolbar(),
                        if (_isPrinting)
                          LinearProgressIndicator(
                            value: _printProgress == 0 ? null : _printProgress,
                            color: AppColors.mSales,
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg,
                              vertical: AppSpace.md,
                            ),
                            child: Center(
                              child: RepaintBoundary(
                                key: _receiptKey,
                                child: PosReceiptDocument(
                                  order: order,
                                  docType: _docType,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _toolbar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.sm,
        AppSpace.gutter,
        AppSpace.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<PosDocType>(
            segments: [
              ButtonSegment(
                value: PosDocType.invoice,
                label: const Text('POS Invoice'),
                icon: Icon(PhosphorIconsDuotone.receipt),
              ),
              ButtonSegment(
                value: PosDocType.challan,
                label: const Text('POS Challan'),
                icon: Icon(PhosphorIconsDuotone.truck),
              ),
            ],
            selected: {_docType},
            onSelectionChanged: (selection) {
              setState(() => _docType = selection.first);
            },
          ),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: [
              Icon(
                PhosphorIconsDuotone.bluetooth,
                size: 16,
                color: _printer == null
                    ? AppColors.inkMuted
                    : AppColors.mSales,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _printer == null
                      ? 'No printer selected'
                      : '${_printer!.name} · ${_printer!.transportLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: _printer == null
                        ? AppColors.inkMuted
                        : AppColors.ink,
                  ),
                ),
              ),
              AppPillButton(
                icon: PhosphorIconsDuotone.bluetooth,
                label: _printer == null ? 'Select printer' : 'Change',
                onTap: _choosePrinter,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
