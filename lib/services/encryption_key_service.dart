import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionKeyService {
  static const _storageKey = 'db_encryption_key';
  static const _keyLength = 32;
  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  final FlutterSecureStorage _storage;

  EncryptionKeyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final key = List.generate(
      _keyLength,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();

    await _storage.write(key: _storageKey, value: key);
    return key;
  }
}
