import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// One write as the platform saw it: the value and the fully serialised
/// options, which is what the native side reads its protections from.
class RecordedWrite {
  RecordedWrite(this.key, this.value, this.options);

  final String key;
  final String value;
  final Map<String, String> options;
}

/// An in-memory [FlutterSecureStoragePlatform].
///
/// Installed as `FlutterSecureStoragePlatform.instance` so the real
/// `FlutterSecureStorage` runs on top of it — which means the options that
/// reach the platform are the ones the service actually passed, serialised
/// the way the plugin serialises them, not a mock's view of the Dart call.
/// Every write is recorded with its options so a test can pin them.
class FakeSecureStoragePlatform extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  final Map<String, String> values = {};
  final List<RecordedWrite> writes = [];

  /// When set, every write throws it (after being recorded), simulating a
  /// store that refuses.
  Object? writeFailure;

  /// When set, every read throws it.
  Object? readFailure;

  /// Keys whose stored value this device cannot decrypt — what an Android
  /// data directory copied from another phone looks like to the plugin: the
  /// value is there, reading it throws, and the next write replaces it.
  final Set<String> unreadableKeys = {};

  /// When set, a write it returns true for throws instead of landing.
  bool Function(String key, String value)? rejectWrite;

  /// When true, writes are recorded but do not change [values] — a store that
  /// reports success and then does not read back.
  bool writesVanish = false;

  /// Options of the most recent write to [key], or null if none.
  Map<String, String>? lastOptionsFor(String key) {
    for (final write in writes.reversed) {
      if (write.key == key) return write.options;
    }
    return null;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    writes.add(RecordedWrite(key, value, Map.of(options)));
    if (writeFailure != null) throw writeFailure!;
    if (rejectWrite?.call(key, value) ?? false) {
      throw PlatformException(code: 'write-rejected', message: key);
    }
    if (writesVanish) return;
    values[key] = value;
    unreadableKeys.remove(key);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (readFailure != null) throw readFailure!;
    if (unreadableKeys.contains(key)) {
      throw PlatformException(
        code: 'Exception encountered',
        message: 'read',
        details: 'javax.crypto.AEADBadTagException',
      );
    }
    return values[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    values.remove(key);
    unreadableKeys.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => Map.of(values);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    values.clear();
  }
}

/// Thrown by [DiesAfterDelete] for every call once the process is "dead":
/// nothing after that instant runs.
class ProcessDied extends Error {
  @override
  String toString() => 'ProcessDied: the process was killed mid-rewrite';
}

/// Stands in for the process dying the instant after [key] was deleted — the
/// moment in a delete-then-add rewrite with no main item on disk. Everything
/// up to and including that delete reaches [inner]; every call after it
/// throws [ProcessDied]. What [inner] holds afterwards is what the next
/// launch finds.
class DiesAfterDelete extends FlutterSecureStoragePlatform
    with MockPlatformInterfaceMixin {
  DiesAfterDelete(this.inner, {required this.key});

  final FakeSecureStoragePlatform inner;
  final String key;
  bool dead = false;

  void _alive() {
    if (dead) throw ProcessDied();
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) {
    _alive();
    return inner.write(key: key, value: value, options: options);
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) {
    _alive();
    return inner.read(key: key, options: options);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) {
    _alive();
    return inner.containsKey(key: key, options: options);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    _alive();
    await inner.delete(key: key, options: options);
    if (key == this.key) dead = true;
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) {
    _alive();
    return inner.readAll(options: options);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) {
    _alive();
    return inner.deleteAll(options: options);
  }
}
