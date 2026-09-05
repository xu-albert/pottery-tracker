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
    if (!writesVanish) values[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    if (readFailure != null) throw readFailure!;
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
