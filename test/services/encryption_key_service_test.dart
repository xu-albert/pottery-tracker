import 'package:flutter/foundation.dart';
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
const _migratingName = 'db_encryption_key_migrating';
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

    /// What the released app stored the key under (the plugin default), and
    /// what nothing may ever be written under again.
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
      // The copy that guards the delete-then-add is itself hardened: it must
      // never enter a backup either.
      verify(
        () => storage.write(
          key: _migratingName,
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

    test('when the hardened add does not stick, nothing is written under the '
        'legacy options: the copy stays and the marker is unset', () async {
      final stored = <String, String>{_keyName: _legacyKey};
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async {
        final key = i.namedArguments[#key] as String;
        // The hardened write deletes and fails to re-add.
        if (key == _keyName) {
          stored.remove(_keyName);
          return;
        }
        stored[key] = i.namedArguments[#value] as String;
      });
      when(
        () => storage.read(
          key: any(named: 'key'),
          iOptions: any(named: 'iOptions'),
          aOptions: any(named: 'aOptions'),
        ),
      ).thenAnswer((i) async => stored[i.namedArguments[#key] as String]);

      await onMock.hardenStoredKey(_legacyKey);

      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
          iOptions: any(named: 'iOptions', that: legacyIos),
          aOptions: any(named: 'aOptions'),
        ),
      );
      expect(stored.containsKey(_keyName), isFalse);
      expect(stored[_migratingName], _legacyKey);
      expect(stored.containsKey(_markerName), isFalse);
      expect(await onMock.readKey(), _legacyKey);
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

    test('iOS: a store failure propagates rather than reading as "no key"', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      platform.values[_keyName] = _legacyKey;
      platform.readFailure = PlatformException(code: 'locked');
      expect(service.readKey(), throwsA(isA<PlatformException>()));
    });

    test(
      'Android: a value this device cannot decrypt reads as no key',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        platform.values[_keyName] = _legacyKey;
        platform.unreadableKeys.add(_keyName);
        expect(await service.readKey(), isNull);
      },
    );

    test(
      'Android: a read failure that is not a decrypt failure propagates',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        platform.values[_keyName] = _legacyKey;
        platform.readFailure = PlatformException(
          code: 'Exception encountered',
          message: 'read',
          details: 'java.lang.NullPointerException: storageCipher',
        );
        expect(service.readKey(), throwsA(isA<PlatformException>()));
      },
    );

    test(
      'falls back to the migrating copy when the item itself is gone',
      () async {
        platform.values[_migratingName] = _legacyKey;
        expect(await service.readKey(), _legacyKey);
      },
    );

    test('prefers the item over a copy left behind', () async {
      platform.values[_keyName] = _legacyKey;
      platform.values[_migratingName] = 'staleCopy0123456789abcdefghijklm';
      expect(await service.readKey(), _legacyKey);
    });

    test('readMigratingCopy reads the copy alone', () async {
      platform.values[_keyName] = _legacyKey;
      expect(await service.readMigratingCopy(), isNull);
      platform.values[_migratingName] = 'staleCopy0123456789abcdefghijklm';
      expect(
        await service.readMigratingCopy(),
        'staleCopy0123456789abcdefghijklm',
      );
    });

    group('iOS, before the first unlock', () {
      EncryptionKeyService withProtectedData(Future<bool?> Function() answer) =>
          EncryptionKeyService(
            storage: const FlutterSecureStorage(
              iOptions: EncryptionKeyService.iosOptions,
              aOptions: EncryptionKeyService.androidOptions,
            ),
            protectedDataAvailable: answer,
          );

      setUp(() {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
      });

      test('nothing stored while protected data is unavailable is not '
          '"no key"', () {
        final locked = withProtectedData(() async => false);
        expect(locked.readKey(), throwsA(isA<KeyStoreUnavailableException>()));
      });

      test(
        'nothing stored with protected data available reads as null',
        () async {
          final unlocked = withProtectedData(() async => true);
          expect(await unlocked.readKey(), isNull);
        },
      );

      test('a stored key is returned without asking', () async {
        platform.values[_keyName] = _legacyKey;
        final unasked = withProtectedData(
          () async => throw StateError('asked'),
        );
        expect(await unasked.readKey(), _legacyKey);
      });

      test(
        'a platform with no such notion answers null and is trusted',
        () async {
          final unknown = withProtectedData(() async => null);
          expect(await unknown.readKey(), isNull);
        },
      );

      test('Android never asks', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final locked = withProtectedData(() async => false);
        expect(await locked.readKey(), isNull);
      });
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
        expect(platform.values.containsKey(_migratingName), isFalse);
      },
    );

    test('keeps a copy on disk for the whole of the delete-then-add', () async {
      platform.values[_keyName] = _legacyKey;
      final original = platform;
      final copyAtDelete = <String?>[];
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) => original.values[key] = value,
        onDelete: (key) {
          if (key == _keyName) {
            copyAtDelete.add(original.values[_migratingName]);
          }
          original.values.remove(key);
        },
      );

      await service.hardenStoredKey(_legacyKey);

      expect(copyAtDelete, [_legacyKey]);
    });

    test('a process that dies between the delete and the add leaves the copy, '
        'and the next launch finishes the rewrite from it', () async {
      platform.values[_keyName] = _legacyKey;
      FlutterSecureStoragePlatform.instance = DiesAfterDelete(
        platform,
        key: _keyName,
      );

      await expectLater(
        service.hardenStoredKey(_legacyKey),
        throwsA(isA<ProcessDied>()),
      );
      expect(platform.values.containsKey(_keyName), isFalse);
      expect(platform.values[_migratingName], _legacyKey);

      FlutterSecureStoragePlatform.instance = platform;
      expect(await service.readKey(), _legacyKey);
      await service.hardenStoredKey(_legacyKey);

      expect(platform.values[_keyName], _legacyKey);
      expect(platform.values[_markerName], '2');
      expect(platform.values.containsKey(_migratingName), isFalse);
    });

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

    test('when the hardened write does not stick, the copy survives, the '
        'marker is left unset, and the next launch finishes', () async {
      platform.values[_keyName] = _legacyKey;
      final original = platform;
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) {
          // The hardened add of the item vanishes.
          if (key == _keyName) return;
          original.values[key] = value;
        },
      );

      await service.hardenStoredKey(_legacyKey);

      expect(original.values.containsKey(_keyName), isFalse);
      expect(original.values[_migratingName], _legacyKey);
      expect(original.values.containsKey(_markerName), isFalse);
      expect(original.writes.where((w) => w.key == _keyName), hasLength(1));

      FlutterSecureStoragePlatform.instance = original;
      expect(await service.readKey(), _legacyKey);
      await service.hardenStoredKey(_legacyKey);

      expect(original.values[_keyName], _legacyKey);
      expect(original.values[_markerName], '2');
      expect(original.values.containsKey(_migratingName), isFalse);
    });

    test('a hardened write that throws leaves the copy the same way', () async {
      platform.values[_keyName] = _legacyKey;
      final original = platform;
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) {
          if (key == _keyName) {
            throw PlatformException(code: 'interaction-not-allowed');
          }
          original.values[key] = value;
        },
      );

      await service.hardenStoredKey(_legacyKey);

      expect(original.values.containsKey(_keyName), isFalse);
      expect(original.values[_migratingName], _legacyKey);
      expect(original.values.containsKey(_markerName), isFalse);
      expect(await service.readKey(), _legacyKey);
    });

    test('when nothing can be written, the key is left where it was and the '
        'marker unset', () async {
      platform.values[_keyName] = _legacyKey;
      platform.writesVanish = true;

      await service.hardenStoredKey(_legacyKey);

      expect(platform.values[_keyName], _legacyKey);
      expect(platform.values.containsKey(_markerName), isFalse);
      expect(platform.values.containsKey(_migratingName), isFalse);
    });

    test('throws when the rewrite loses both the item and its copy', () async {
      platform.values[_keyName] = _legacyKey;
      final original = platform;
      FlutterSecureStoragePlatform.instance = _ScriptedPlatform(
        original,
        onWrite: (key, value, options) {
          if (key == _migratingName) original.values[key] = value;
        },
        onDelete: (key) => original.values.clear(),
      );

      await expectLater(
        service.hardenStoredKey(_legacyKey),
        throwsA(isA<KeyStorageException>()),
      );
      expect(original.values.containsKey(_markerName), isFalse);
    });

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
        expect(original.values.containsKey(_migratingName), isFalse);
        expect(original.writes.where((w) => w.key == _keyName), hasLength(1));
      },
    );
  });

  group('storeKey', () {
    test(
      'stores the given key under the pinned options and marks it',
      () async {
        await service.storeKey(_legacyKey);
        expect(platform.values[_keyName], _legacyKey);
        expect(platform.values[_markerName], '2');
        expect(platform.values.containsKey(_migratingName), isFalse);
      },
    );

    test('replaces a key already stored', () async {
      platform.values[_keyName] = 'stale';
      await service.storeKey(_legacyKey);
      expect(platform.values[_keyName], _legacyKey);
    });

    test('refuses to report a key that did not read back', () {
      platform.values[_keyName] = 'stale';
      platform.writesVanish = true;
      expect(service.storeKey(_legacyKey), throwsA(isA<KeyStorageException>()));
    });
  });
}

class _MockStorage extends Mock implements FlutterSecureStorage {}

/// Wraps a [FakeSecureStoragePlatform] and lets a test script each write's
/// effect while the fake keeps recording them.
class _ScriptedPlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  _ScriptedPlatform(this._inner, {required this.onWrite, this.onDelete});

  final FakeSecureStoragePlatform _inner;
  final void Function(String key, String value, Map<String, String> options)
  onWrite;
  final void Function(String key)? onDelete;

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
  }) async {
    if (onDelete != null) return onDelete!(key);
    await _inner.delete(key: key, options: options);
  }

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _inner.readAll(options: options);

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _inner.deleteAll(options: options);
}
