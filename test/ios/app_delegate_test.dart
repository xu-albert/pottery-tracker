import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The SQLCipher key is a Keychain item and the database it opens is a file
/// in Documents. Native code runs before Dart, so a Keychain deletion there
/// leaves `LocalDatabaseBootstrap` holding an encrypted journal with no key —
/// unrecoverable for a local-only user. No native app source may delete a
/// Keychain item; the secure-storage plugin owns every one the app keeps.
///
/// Read as text because the Runner cannot be built in this suite. The launch
/// itself (an existing install keeps its key) is a device check; see
/// docs/local-database-key.md.
void main() {
  final sources = Directory('ios/Runner')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => RegExp(r'\.(swift|m|mm|h)$').hasMatch(f.path))
      .toList();

  test('the Runner has native sources to check', () {
    expect(
      sources.map((f) => f.uri.pathSegments.last),
      contains('AppDelegate.swift'),
    );
  });

  test('no native Runner source deletes Keychain items', () {
    for (final file in sources) {
      expect(
        file.readAsStringSync(),
        isNot(contains('SecItemDelete')),
        reason: '${file.path} deletes Keychain items before Dart runs',
      );
    }
  });
}
