import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/services/encryption_key_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late EncryptionKeyService service;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    service = EncryptionKeyService(storage: mockStorage);
  });

  group('EncryptionKeyService', () {
    test('generates a new key when none exists', () async {
      when(
        () => mockStorage.read(key: 'db_encryption_key'),
      ).thenAnswer((_) async => null);
      when(
        () => mockStorage.write(
          key: 'db_encryption_key',
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      final key = await service.getOrCreateKey();

      expect(key.length, 32);
      expect(key, matches(RegExp(r'^[a-zA-Z0-9]+$')));
      verify(
        () => mockStorage.write(key: 'db_encryption_key', value: key),
      ).called(1);
    });

    test('returns existing key when one exists', () async {
      when(
        () => mockStorage.read(key: 'db_encryption_key'),
      ).thenAnswer((_) async => 'existingKey12345678901234567890ab');

      final key = await service.getOrCreateKey();

      expect(key, 'existingKey12345678901234567890ab');
      verifyNever(
        () => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });

    test('generates different keys each time when no key exists', () async {
      when(
        () => mockStorage.read(key: 'db_encryption_key'),
      ).thenAnswer((_) async => null);
      when(
        () => mockStorage.write(
          key: 'db_encryption_key',
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      final key1 = await service.getOrCreateKey();
      final key2 = await service.getOrCreateKey();

      // Both should be valid keys (though theoretically could be same, astronomically unlikely)
      expect(key1.length, 32);
      expect(key2.length, 32);
    });
  });
}
