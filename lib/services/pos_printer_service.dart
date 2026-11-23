import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'esc_pos_builder.dart';

enum PosPrinterTransport { ble, classic }

class PosPrinterDevice {
  const PosPrinterDevice({
    required this.id,
    required this.name,
    required this.transport,
    this.isPaired = false,
  });

  /// BLE remote id or classic SPP MAC address.
  final String id;
  final String name;
  final PosPrinterTransport transport;
  final bool isPaired;

  String get transportLabel =>
      transport == PosPrinterTransport.ble ? 'Bluetooth LE' : 'Bluetooth (SPP)';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        'isPaired': isPaired,
      };

  static PosPrinterDevice? fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    final name = json['name']?.toString();
    final transportName = json['transport']?.toString();
    if (id == null || id.isEmpty || name == null || transportName == null) {
      return null;
    }

    PosPrinterTransport? transport;
    for (final value in PosPrinterTransport.values) {
      if (value.name == transportName) {
        transport = value;
        break;
      }
    }
    if (transport == null) return null;

    return PosPrinterDevice(
      id: id,
      name: name,
      transport: transport,
      isPaired: json['isPaired'] == true,
    );
  }
}

class PosPrinterException implements Exception {
  PosPrinterException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Discovers, remembers and prints to Bluetooth POS printers.
///
/// Supports BLE printers (flutter_blue_plus) and classic SPP printers
/// (print_bluetooth_thermal). Receipts are printed as a raster image of the
/// on-screen preview, so the paper matches the preview exactly.
class PosPrinterService {
  PosPrinterService._internal();

  static final PosPrinterService instance = PosPrinterService._internal();

  static const String _savedPrinterKey = 'pos_printer_saved';
  static const int _bleChunkSize = 180;
  static const int _classicChunkSize = 400;
  static const Duration _chunkDelay = Duration(milliseconds: 30);

  BluetoothDevice? _connectedBleDevice;

  Future<PosPrinterDevice?> getSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_savedPrinterKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PosPrinterDevice.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePrinter(PosPrinterDevice printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedPrinterKey, jsonEncode(printer.toJson()));
  }

  Future<List<PosPrinterDevice>> getPairedDevices() async {
    final devices = <PosPrinterDevice>[];

    try {
      if (await PrintBluetoothThermal.bluetoothEnabled) {
        final paired = await PrintBluetoothThermal.pairedBluetooths;
        for (final info in paired) {
          final mac = info.macAdress.trim();
          if (mac.isEmpty) continue;
          devices.add(PosPrinterDevice(
            id: mac,
            name: info.name.trim().isEmpty ? mac : info.name.trim(),
            transport: PosPrinterTransport.classic,
            isPaired: true,
          ));
        }
      }
    } catch (_) {
      // Classic Bluetooth may be unavailable; BLE devices are still listed.
    }

    try {
      if (await FlutterBluePlus.isSupported) {
        for (final device in await FlutterBluePlus.bondedDevices) {
          final name = device.platformName.trim();
          devices.add(PosPrinterDevice(
            id: device.remoteId.str,
            name: name.isEmpty ? device.remoteId.str : name,
            transport: PosPrinterTransport.ble,
            isPaired: true,
          ));
        }
      }
    } catch (_) {
      // Ignore: bonded BLE list is best-effort.
    }

    return _sorted(devices);
  }

  Future<List<PosPrinterDevice>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    await _ensureBluetoothPermissions();

    if (!await FlutterBluePlus.isSupported) {
      throw PosPrinterException('Bluetooth LE is not available on this device.');
    }

    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw PosPrinterException('Turn Bluetooth on, then scan again.');
    }

    final found = <String, PosPrinterDevice>{};
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final remoteId = result.device.remoteId.str;
        final advName = result.advertisementData.advName.trim();
        final platformName = result.device.platformName.trim();
        final name = advName.isNotEmpty
            ? advName
            : (platformName.isNotEmpty ? platformName : remoteId);
        found[remoteId] = PosPrinterDevice(
          id: remoteId,
          name: name,
          transport: PosPrinterTransport.ble,
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
    } catch (error) {
      throw PosPrinterException('Scan failed: $error');
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }

    return _sorted(found.values.toList());
  }

  Future<void> printPng(
    Uint8List pngBytes, {
    required PosPrinterDevice printer,
    int dotsPerLine = 576,
    void Function(int sent, int total)? onProgress,
  }) async {
    final commands = await buildPngReceiptCommands(
      pngBytes,
      dotsPerLine: dotsPerLine,
    );

    await _send(printer, commands, onProgress);
  }

  Future<void> printTestPage({
    required PosPrinterDevice printer,
    int dotsPerLine = 576,
  }) async {
    final commands = await buildTestPageCommands(dotsPerLine: dotsPerLine);
    await _send(printer, commands, null);
  }

  Future<void> disconnect() async {
    final device = _connectedBleDevice;
    _connectedBleDevice = null;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    try {
      if (await PrintBluetoothThermal.connectionStatus) {
        await PrintBluetoothThermal.disconnect;
      }
    } catch (_) {}
  }

  Future<void> _send(
    PosPrinterDevice printer,
    List<int> commands,
    void Function(int sent, int total)? onProgress,
  ) async {
    if (commands.isEmpty) {
      throw PosPrinterException('Nothing to print.');
    }

    if (printer.transport == PosPrinterTransport.classic) {
      await _sendClassic(printer, commands, onProgress);
    } else {
      await _sendBle(printer, commands, onProgress);
    }
  }

  Future<void> _sendClassic(
    PosPrinterDevice printer,
    List<int> commands,
    void Function(int sent, int total)? onProgress,
  ) async {
    await _ensureBluetoothPermissions();

    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw PosPrinterException('Turn Bluetooth on, then try again.');
    }

    final connected =
        await PrintBluetoothThermal.connect(macPrinterAddress: printer.id);
    if (!connected) {
      throw PosPrinterException(
        'Could not connect to ${printer.name}. Pair the printer in Android Bluetooth settings first.',
      );
    }

    try {
      var sent = 0;
      while (sent < commands.length) {
        final end = (sent + _classicChunkSize) > commands.length
            ? commands.length
            : sent + _classicChunkSize;
        final chunk = commands.sublist(sent, end);
        final written = await PrintBluetoothThermal.writeBytes(chunk);
        if (!written) {
          throw PosPrinterException('The printer stopped accepting data.');
        }
        sent = end;
        onProgress?.call(sent, commands.length);
        await Future<void>.delayed(_chunkDelay);
      }
    } finally {
      try {
        await PrintBluetoothThermal.disconnect;
      } catch (_) {}
    }
  }

  Future<void> _sendBle(
    PosPrinterDevice printer,
    List<int> commands,
    void Function(int sent, int total)? onProgress,
  ) async {
    await _ensureBluetoothPermissions();

    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw PosPrinterException('Turn Bluetooth on, then try again.');
    }

    BluetoothDevice device;
    try {
      device = BluetoothDevice.fromId(printer.id);
      await device.connect(timeout: const Duration(seconds: 20));
    } catch (error) {
      throw PosPrinterException('Could not connect to ${printer.name}: $error');
    }

    _connectedBleDevice = device;

    try {
      final services = await device.discoverServices();
      final characteristic = _writableCharacteristic(services);
      if (characteristic == null) {
        throw PosPrinterException(
          '${printer.name} has no writable print characteristic.',
        );
      }

      final withoutResponse = characteristic.properties.writeWithoutResponse;
      var sent = 0;
      while (sent < commands.length) {
        final end = (sent + _bleChunkSize) > commands.length
            ? commands.length
            : sent + _bleChunkSize;
        final chunk = commands.sublist(sent, end);
        await characteristic.write(chunk, withoutResponse: withoutResponse);
        sent = end;
        onProgress?.call(sent, commands.length);
        await Future<void>.delayed(_chunkDelay);
      }
    } finally {
      try {
        await device.disconnect();
      } catch (_) {}
      if (identical(_connectedBleDevice, device)) {
        _connectedBleDevice = null;
      }
    }
  }

  BluetoothCharacteristic? _writableCharacteristic(
    List<BluetoothService> services,
  ) {
    final writable = <BluetoothCharacteristic>[];
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristic.properties.write ||
            characteristic.properties.writeWithoutResponse) {
          writable.add(characteristic);
        }
      }
    }

    if (writable.isEmpty) return null;

    const preferredServices = ['ffe0', 'ff00', '18f0', 'e7810a71'];
    for (final characteristic in writable) {
      final serviceId = characteristic.serviceUuid.str.toLowerCase();
      if (preferredServices.any(serviceId.contains)) {
        return characteristic;
      }
    }

    return writable.first;
  }

  Future<void> _ensureBluetoothPermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();

    if (scan.isPermanentlyDenied || connect.isPermanentlyDenied) {
      throw PosPrinterException(
        'Bluetooth permission is blocked. Enable "Nearby devices" for PPHL Attendance in Android settings.',
      );
    }

    if (!scan.isGranted || !connect.isGranted) {
      throw PosPrinterException(
        'Bluetooth permission is required to print. Allow "Nearby devices" and try again.',
      );
    }
  }

  List<PosPrinterDevice> _sorted(List<PosPrinterDevice> devices) {
    devices.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return devices;
  }
}
