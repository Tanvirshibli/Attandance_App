import 'package:employee_attendance/models/face_registration_data.dart';
import 'package:employee_attendance/services/biometric_login_service.dart';
import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};
  var failWrites = false;

  setUp(() {
    store.clear();
    failWrites = false;
    FaceRecognitionService().clearRegistrationMemory();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          if (failWrites) {
            throw PlatformException(code: 'write_failed');
          }
          store[key!] = args['value'] as String;
          return null;
        case 'read':
          return store[key];
        case 'delete':
          store.remove(key);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(key);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  FaceRegistrationData template() {
    final embedding = List<double>.generate(8, (i) => i / 10);
    return FaceRegistrationData(
      avgEmbedding: embedding,
      captureEmbeddings: [List<double>.from(embedding)],
      adaptiveEmbeddings: const [],
      captureCount: 1,
      templateVersion: FaceRecognitionService.templateVersion,
      registeredAt: '2026-11-16T10:00:00Z',
      registrationQuality: null,
      status: 'active',
    );
  }

  test('a restored device template is ready without a stored token', () async {
    final face = FaceRecognitionService();
    face.hydrateRegistration(template());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await face.hasStoredFace(), isTrue);

    expect(
      await BiometricLoginService.instance.faceLoginBlocker(face),
      FaceLoginBlocker.ready,
    );
  });

  test('no template and no credential is reported as not linked', () async {
    final face = FaceRecognitionService();

    expect(
      await BiometricLoginService.instance.faceLoginBlocker(face),
      FaceLoginBlocker.notLinked,
    );
  });

  test('a failed template write is reported instead of silently succeeding',
      () async {
    final face = FaceRecognitionService();
    face.hydrateRegistration(template());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    failWrites = true;
    expect(await face.persistCurrentRegistration(), isFalse);

    failWrites = false;
    expect(await face.persistCurrentRegistration(), isTrue);
  });

  test('secondary blocker messages do not tell a linked user to re-register',
      () {
    expect(
      BiometricLoginService.faceNotLinkedMessage.toLowerCase(),
      isNot(contains('register your face')),
    );
    expect(
      BiometricLoginService.faceRegistrationUnavailableMessage.toLowerCase(),
      isNot(contains('register your face')),
    );
  });
}
