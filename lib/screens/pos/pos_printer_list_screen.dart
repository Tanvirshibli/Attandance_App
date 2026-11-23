import 'package:flutter/material.dart';

import '../../services/pos_printer_service.dart';
import '../../widgets/ui/ui.dart';

/// Lists paired and discovered Bluetooth POS printers.
///
/// Tapping a printer stores it as the default and returns it to the caller.
class PosPrinterListScreen extends StatefulWidget {
  const PosPrinterListScreen({super.key});

  @override
  State<PosPrinterListScreen> createState() => _PosPrinterListScreenState();
}

class _PosPrinterListScreenState extends State<PosPrinterListScreen> {
  final PosPrinterService _service = PosPrinterService.instance;

  List<PosPrinterDevice> _devices = const [];
  PosPrinterDevice? _saved;
  bool _isLoading = true;
  bool _isScanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPaired();
  }

  Future<void> _loadPaired() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final devices = await _service.getPairedDevices();
      final saved = await _service.getSavedPrinter();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _saved = saved;
        _isLoading = false;
      });
    } on PosPrinterException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = error.message;
      });
    }
  }

  Future<void> _scan() async {
    setState(() {
      _isScanning = true;
      _error = null;
    });

    try {
      final found = await _service.scan();
      if (!mounted) return;
      setState(() {
        _devices = _mergeDevices(_devices, found);
        _isScanning = false;
      });
    } on PosPrinterException catch (error) {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _error = error.message;
      });
    }
  }

  List<PosPrinterDevice> _mergeDevices(
    List<PosPrinterDevice> current,
    List<PosPrinterDevice> found,
  ) {
    final byId = <String, PosPrinterDevice>{
      for (final device in current) device.id: device,
    };
    for (final device in found) {
      byId[device.id] = device;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return merged;
  }

  Future<void> _select(PosPrinterDevice device) async {
    await _service.savePrinter(device);
    if (!mounted) return;
    Navigator.pop(context, device);
  }

  Future<void> _testPrint(PosPrinterDevice device) async {
    try {
      await _service.printTestPage(printer: device);
      if (!mounted) return;
      _message('Test page sent to ${device.name}.');
    } on PosPrinterException catch (error) {
      if (!mounted) return;
      _message(error.message);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('POS Printers'),
        actions: [
          IconButton(
            tooltip: 'Scan for printers',
            onPressed: _isScanning ? null : _scan,
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(PhosphorIconsDuotone.magnifyingGlass),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPaired,
        color: AppColors.mSales,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.all(AppSpace.gutter),
          children: [
            Text(
              'Pair the printer in Android Bluetooth settings, then pick it here. '
              'Receipts print as an image of the preview, so 58 mm and 80 mm '
              'printers both keep the same layout.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              AppEmptyState(
                icon: AppIcons.error,
                title: 'Bluetooth unavailable',
                subtitle: _error,
                onRetry: _loadPaired,
              )
            else if (_devices.isEmpty)
              AppEmptyState(
                icon: AppIcons.info,
                title: 'No printers found',
                subtitle:
                    'Pair a POS printer in Android settings, or scan for a Bluetooth LE printer.',
                onRetry: _loadPaired,
              )
            else
              for (final device in _devices)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: AppCard(
                    onTap: () => _select(device),
                    child: Row(
                      children: [
                        Icon(
                          device.isPaired
                              ? PhosphorIconsDuotone.checkCircle
                              : PhosphorIconsDuotone.bluetooth,
                          color: AppColors.mSales,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.name, style: AppType.bodyStrong),
                              Text(
                                '${device.transportLabel} · ${device.id}'
                                '${_saved?.id == device.id ? ' · selected' : ''}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _testPrint(device),
                          child: const Text('Test'),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
