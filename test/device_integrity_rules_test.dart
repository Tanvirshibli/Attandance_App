import 'package:employee_attendance/services/device_integrity_service.dart';
import 'package:employee_attendance/services/integrity_lock_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position _fix({
  bool isMocked = false,
  double accuracy = 8,
  double latitude = 23.8103,
  double longitude = 90.4125,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 11, 15, 10, 0, 0),
    accuracy: accuracy,
    altitude: 10,
    altitudeAccuracy: 2,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: isMocked,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final integrity = DeviceIntegrityService.instance;

  setUp(() => integrity.resetForNewSession());

  test(
    'a clean fix is not blocked when the phone reports mock location as allowed',
    () async {
      integrity.debugSetMockProbe(
        opMode: 'allowed',
        providerPackage: 'com.example.fakegps',
        adbEnabled: true,
      );

      expect(await integrity.checkPosition(_fix()), isNull);
    },
  );

  test('a probe with no provider package is not blocked either', () async {
    integrity.debugSetMockProbe(opMode: 'default');

    expect(await integrity.checkPosition(_fix()), isNull);
  });

  test('the probe stays available as diagnostics', () async {
    integrity.debugSetMockProbe(
      opMode: 'allowed',
      providerPackage: 'com.example.fakegps',
      adbEnabled: true,
    );
    await integrity.checkPosition(_fix());

    expect(integrity.mockDiagnostics['opMode'], 'allowed');
    expect(integrity.mockDiagnostics['providerPackage'], 'com.example.fakegps');
    expect(integrity.mockDiagnostics['adbEnabled'], isTrue);
  });

  test('a fix the OS flags as mocked is still refused', () async {
    integrity.debugSetMockProbe(opMode: 'default');

    final violation = await integrity.checkPosition(_fix(isMocked: true));

    expect(violation?.type, IntegrityType.gpsMock);
  });

  test('a fix too coarse to place a site is refused', () async {
    integrity.debugSetMockProbe(opMode: 'default');

    final violation = await integrity.checkPosition(_fix(accuracy: 150));

    expect(violation?.type, IntegrityType.gpsUntrusted);
  });

  test('a 0,0 fix is refused', () async {
    integrity.debugSetMockProbe(opMode: 'default');

    final violation =
        await integrity.checkPosition(_fix(latitude: 0, longitude: 0));

    expect(violation?.type, IntegrityType.gpsUntrusted);
  });

  test('a retired false-positive lock is dropped on upgrade', () {
    const retired = IntegrityViolation(
      type: IntegrityType.mockLocationApp,
      title: 'Mock location is switched on',
      message: 'Old wording',
    );
    const mocked = IntegrityViolation(
      type: IntegrityType.gpsMock,
      title: 'Fake GPS detected',
      message: 'Android flagged this position as a mock fix.',
    );

    expect(IntegrityLockService.isRetiredFalsePositive(retired), isTrue);
    expect(IntegrityLockService.isRetiredFalsePositive(mocked), isFalse);
  });
}
