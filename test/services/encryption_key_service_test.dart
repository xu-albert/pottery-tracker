import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pottery_tracker/services/encryption_key_service.dart';

import '../helpers/fake_secure_storage.dart';

const _keyName = 'db_encryption_key';
const _markerName = 'db_encryption_key_storage_version';
const _legacyKey = 'existingKey12345678901234567890ab';

/// What the native side must receive for the key to be left out of backups
/// on iOS and to use the modern ciphers on Android. These literal strings are
/// the contract with the plugin's Swift and Java, pinned so a default change
/// upstream or a slip here cannot silently move the key back.
const _hardenedIos = {
  'accessibility': 'first_unlock_this_device',
  'synchronizable': 'false',
};
const _hardenedAndroid = {
  'encryptedSharedPreferences': 'false',
  'keyCipherAlgorithm': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
  'storageCipherAlgorithm': 'AES_GCM_NoPadding',
};

void main() {
  late FakeSecureStoragePlatform platform;
  late EncryptionKeyService service;

  setUp(() {
    platform = FakeSecureStoragePlatform();
    FlutterSecureStoragePlatform.instance = platform;
    service = EncryptionKeyService(
      storage: const FlutterSecureStorage(
        iOptions: EncryptionKeyService.iosOptions,
        aOptions: EncryptionKeyService.androidOptions,
      ),
    );
  });

  group('pinned options', () {
    test('iOS: this-device-only after first unlock, never synchronised', () {
      final map = EncryptionKeyService.iosOptions.toMap();
      for (final entry in _hardenedIos.entries) {
        expect(map, containsPair(entry.key, entry.value));
      }
    });

    test('Android: KeyStore path on RSA-OAEP + AES-GCM', () {
      final map = EncryptionKeyService.androidOptions.toMap();
      for (final entry in _hardenedAndroid.entries) {
        expect(map, containsPair(entry.key, entry.value));
      }
    });

    test('the legacy options are what the plugin defaulted to', () {
      // Pinned so the fallback rewrite puts the key back exactly where the
      // released app kept it, and nowhere new.
      final legacy = EncryptionKeyService.legacyIosOptions.toMap();
      expect(legacy, containsPair('accessibility', 'unlocked'));
      expect(legacy, containsPair('synchronizable', 'false'));
      expect(
        EncryptionKeyService.legacyIosOptions.toMap()['accessibility'],
        IOSOptions.defaultOptions.toMap()['accessibility'],
      );
    });

    test('the default storage carries the pinned options', () {
      expect(
        EncryptionKeyService.defaultStorage.iOptions.toMap(),
        containsPair('accessibility', 'first_unlock_this_device'),
      );
      expect(
        EncryptionKeyService.defaultStorage.aOptions.toMap(),
        containsPair('storageCipherAlgorithm', 'AES_GCM_NoPadding'),
      );
    });
  });

  /// The plugin serialises the options of the *host* platform, so a test on
  /// macOS or Linux never sees the iOS or Android map reach the native side.
  /// What can be pinned everywhere is the boundary the service controls:
  /// which options it hands the plugin on every call.
  group('every call passes the pinned options', () {
    late _MockStorage storage;
    late EncryptionKeyService onMock;

    final hardenedIos = isA<IOSOptions>().having(
      (o) => o.toMap(),
      'toMap',
      allOf([
        containsPair('accessibility', 'first_unlock_this_device'),
        containsPair('synchronizable', 'false'),
      ]),
    );
    final legacyIos = isA<IOSOptions>().having(
      (o) => o.toMap()['accessibility'],
      'accessibility',
      'unlocked',
    );
    final hardenedAndroid = isA<AndroidOptions>().having(
      (o) => o.toMap(),
      'toMap',
      allOf([
        containsPair('encryptedSharedPreferences', 'false'),
        containsPair(
          'keyCipherAlgorithm',
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
        ),
        containsPair('storageCipherAlgorithm', 'AES_GCM_NoPadding'),
      ]),
    );

    /// The delete that precedes every rewrite must name *no* accessibility,
    /// or it would miss an item stored under a different one.
    final anyAccessibility = isA<IOSOptions>().having(
      (o) => o.toMap().containsKey('accessibility'),
      'names an accessibility',
      isFalse,
    );

    setUp(() {
      storage = _MockStorage();
      onMock = EncryptionKeyService(storage: storage);
      registerFallbackValue(const IOSOptions());
      registerFallbackValue(const AndroidOptions());
      when(
        () => storage.delete(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((_) async {});
    });

    test('readKey', () async {
      when(
        () => storage.read(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((_) async => _legacyKey);

      await onMock.readKey();

      verify(
        () => storage.read(
          key: _keyName,
          iOptions: any(named: 'iOptions', that: hardenedIos),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
    });

    test('createKey writes the key and the marker', () async {
      final stored = <String, String>{};
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async {
        stored[i.namedArguments[#key] as String] =
            i.namedArguments[#value] as String;
      });
      when(
        () => storage.read(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async => stored[i.namedArguments[#key] as String]);

      final key = await onMock.createKey();

      verify(
        () => storage.write(
          key: _keyName,
          value: key,
          iOptions: any(named: 'iOptions', that: hardenedIos),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
      verify(
        () => storage.write(
          key: _markerName,
          value: '2',
          iOptions: any(named: 'iOptions', that: hardenedIos),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions', that: legacyIos),
          aOptions: any(named: 'aOptions'),
        ),
      );
    });

    test('hardenStoredKey rewrites under the hardened options', () async {
      final stored = <String, String>{_keyName: _legacyKey};
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async {
        stored[i.namedArguments[#key] as String] =
            i.namedArguments[#value] as String;
      });
      when(
        () => storage.read(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async => stored[i.namedArguments[#key] as String]);

      await onMock.hardenStoredKey(_legacyKey);

      verify(
        () => storage.delete(
          key: _keyName,
          iOptions: any(named: 'iOptions', that: anyAccessibility),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
      verify(
        () => storage.write(
          key: _keyName,
          value: _legacyKey,
          iOptions: any(named: 'iOptions', that: hardenedIos),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions', that: legacyIos),
          aOptions: any(named: 'aOptions'),
        ),
      );
    });

    test('the fallback, and only the fallback, uses the legacy iOS options — '
        'with the Android options unchanged', () async {
      final stored = <String, String>{_keyName: _legacyKey};
      var writes = 0;
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async {
        // The hardened write deletes and fails to re-add.
        if (writes++ == 0) {
          stored.remove(_keyName);
          return;
        }
        stored[i.namedArguments[#key] as String] =
            i.namedArguments[#value] as String;
      });
      when(
        () => storage.read(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async => stored[i.namedArguments[#key] as String]);

      await onMock.hardenStoredKey(_legacyKey);

      verify(
        () => storage.write(
          key: _keyName,
          value: _legacyKey,
          iOptions: any(named: 'iOptions', that: legacyIos),
          aOptions: any(named: 'aOptions', that: hardenedAndroid),
        ),
      ).called(1);
      expect(stored[_keyName], _legacyKey);
      expect(stored.containsKey(_markerName), isFalse);
    });
  });

  group('readKey', () {
    test('returns null when nothing is stored', () async {
      expect(await service.readKey(), isNull);
    });

    test('treats an empty stored value as no key', () async {
      platform.values[_keyName] = '';
      expect(await service.readKey(), isNull);
    });

    test('returns a key stored by an earlier release', () async {
      platform.values[_keyName] = _legacyKey;
      expect(await service.readKey(), _legacyKey);
    });

    test('a store failure propagates rather than reading as "no key"', () {
      platform.values[_keyName] = _legacyKey;
      platform.readFailure = PlatformException(code: 'locked');
      expect(service.readKey(), throwsA(isA<PlatformException>()));
    });
  });

  group('createKey', () {
    test('generates a 32-character alphanumeric key', () async {
      final key = await service.createKey();
      expect(key.length, 32);
      expect(key, matches(RegExp(r'^[a-zA-Z0-9]+$')));
    });

    test(
      'stores the key under the pinned options and marks the version',
      () async {
        final key = await service.createKey();
        expect(platform.values[_keyName], key);
        expect(platform.values[_markerName], '2');
      },
    );

    test('generates a different key each time', () async {
      final a = await service.createKey();
      final b = await service.createKey();
      expect(a, isNot(b));
    });

    test('refuses to report a key that did not read back', () {
      platform.writesVanish = true;
      expect(service.createKey(), throwsA(isA<KeyStorageException>()));
    });
  });

  group('hardenStoredKey', () {
    test(
      'rewrites a legacy key under the pinned options and marks it',
      () async {
        platform.values[_keyName] = _legacyKey;

        await service.hardenStoredKey(_legacyKey);

        expect(platform.values[_keyName], _legacyKey);
        expect(platform.values[_markerName], '2');
        expect(platform.writes.where((w) => w.key == _keyName), hasLength(1));
      },
    );

    test(
      'does nothing once the marker says the key is already hardened',
      () async {
        platform.values[_keyName] = _legacyKey;
        platform.values[_markerName] = '2';

        await service.hardenStoredKey(_legacyKey);

        expect(platform.writes, isEmpty);
      },
    );

    test('an unrecognised marker version is treated as not hardened', () async {
      platform.values[_keyName] = _legacyKey;
      platform.values[_markerName] = '1';

      await service.hardenStoredKey(_legacyKey);

      expect(platform.values[_markerName], '2');
    });

    test('when the hardened write does not stick, the key is put back under '
        'the legacy options and the marker is left unset', () async {
      platform.values[_keyName] = _legacyKey;
      var attempts = 0;
      // The first write (hardened) vanishes; the fallback lands.
      platform.writesVanish = true;
      platform.values.remove(_keyName);
      // Simulate: hardened write deletes-and-fails-to-add, fallback works.
      final original = platform;
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) {
          attempts++;
          if (attempts == 1) return; // vanish
          original.values[key] = value;
        },
      );

      await service.hardenStoredKey(_legacyKey);

      expect(original.values[_keyName], _legacyKey);
      expect(original.values.containsKey(_markerName), isFalse);
      final fallback = original.writes.last;
      expect(fallback.key, _keyName);
      if (fallback.options.containsKey('accessibility')) {
        expect(fallback.options['accessibility'], 'unlocked');
      }
    });

    test('a failing hardened write falls back the same way', () async {
      platform.values[_keyName] = _legacyKey;
      var attempts = 0;
      final original = platform;
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) {
          attempts++;
          if (attempts == 1) throw PlatformException(code: 'denied');
          original.values[key] = value;
        },
      );

      await service.hardenStoredKey(_legacyKey);

      expect(original.values[_keyName], _legacyKey);
      expect(original.values.containsKey(_markerName), isFalse);
    });

    test(
      'throws when neither the hardened nor the legacy write sticks',
      () async {
        platform.values[_keyName] = _legacyKey;
        platform.writesVanish = true;
        platform.values.remove(_keyName);

        await expectLater(
          service.hardenStoredKey(_legacyKey),
          throwsA(isA<KeyStorageException>()),
        );
        expect(platform.values.containsKey(_markerName), isFalse);
      },
    );

    test(
      'a marker that fails to save does not undo a successful hardening',
      () async {
        platform.values[_keyName] = _legacyKey;
        final original = platform;
        FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
          original,
          onWrite: (key, value, options) {
            if (key == _markerName) throw PlatformException(code: 'full');
            original.values[key] = value;
          },
        );

        await service.hardenStoredKey(_legacyKey);

        expect(original.values[_keyName], _legacyKey);
        expect(original.values.containsKey(_markerName), isFalse);
        // The key is never rewritten under the legacy options in this case.
        expect(original.writes.where((w) => w.key == _keyName), hasLength(1));
      },
    );
  });

  group('storeRecoveredKey', () {
    test(
      'stores the given key under the pinned options and marks it',
      () async {
        await service.storeRecoveredKey(_legacyKey);
        expect(platform.values[_keyName], _legacyKey);
        expect(platform.values[_markerName], '2');
      },
    );

    test('replaces a key already stored', () async {
      platform.values[_keyName] = 'stale';
      await service.storeRecoveredKey(_legacyKey);
      expect(platform.values[_keyName], _legacyKey);
    });
  });
}

class _MockStorage extends Mock implements FlutterSecureStorage {}

/// Wraps a [FakeSecureStoragePlatform] and lets a test script each write's
/// effect while the fake keeps recording them.
class _ScriptedPlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _ScriptedPlatform(this._inner, {required this.onWrite});

  final FakeSecureStoragePlatform _inner;
  final void Function(String key, String value, Map<String, String> options)
  onWrite;

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    _inner.writes.add(RecordedWrite(key, value, Map.of(options)));
    onWrite(key, value, options);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _inner.read(key: key, options: options);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _inner.containsKey(key: key, options: options);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _inner.delete(key: key, options: options);

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _inner.readAll(options: options);

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _inner.deleteAll(options: options);
}
