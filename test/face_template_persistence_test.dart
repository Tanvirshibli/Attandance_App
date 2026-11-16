import 'package:employee_attendance/models/face_registration_data.dart';
import 'package:employee_attendance/services/face_recognition_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the defect that made face sign-in report "no face
/// registered" on every phone.
///
/// `clearRegistrationMemory()` runs whenever the profile comes back without a
/// registration — an omitted field, a partial load, a logout — so it must only
/// drop memory. It used to delete the persisted device copy as well, which left
/// the login screen with nothing to verify against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage is a platform channel; a unit test gets the real
  // persistence logic only through an in-memory stand-in.
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final store = <String, String>{};

  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
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

  FaceRegistrationData template({int version = FaceRecognitionService.templateVersion}) {
    // A short but structurally valid embedding: validity is about shape, not
    // length, when no expected size is supplied.
    final embedding = List<double>.generate(8, (i) => i / 10);
    return FaceRegistrationData(
      avgEmbedding: embedding,
      captureEmbeddings: [List<double>.from(embedding)],
      adaptiveEmbeddings: const [],
      captureCount: 1,
      templateVersion: version,
      registeredAt: '2026-11-16T10:00:00Z',
      registrationQuality: null,
      status: 'active',
    );
  }

  test('clearing memory keeps the device template readable', () async {
    final face = FaceRecognitionService();
    face.hydrateRegistration(template());
    expect(await face.isFaceRegistered(), isTrue);

    // Give the unawaited persist a turn to land.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await face.hasStoredFace(), isTrue);

    face.clearRegistrationMemory();

    expect(await face.isFaceRegistered(), isFalse, reason: 'memory is dropped');
    expect(
      await face.hasStoredFace(),
      isTrue,
      reason: 'the device copy must survive an in-memory clear',
    );

    // And it must still be usable after a cold start.
    expect(await face.restorePersistedRegistration(), isTrue);
  });

  test('an explicit unregister erases the device template', () async {
    final face = FaceRecognitionService();
    face.hydrateRegistration(template());
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await face.deleteRegisteredFace();

    expect(await face.isFaceRegistered(), isFalse);
    expect(await face.hasStoredFace(), isFalse);
  });

  test('a template from another pipeline is refused, not adopted', () async {
    final face = FaceRecognitionService();
    face.hydrateRegistration(template(version: FaceRecognitionService.templateVersion + 1));

    expect(await face.isFaceRegistered(), isFalse);
  });
}
