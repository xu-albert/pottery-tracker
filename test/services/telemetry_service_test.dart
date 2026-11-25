import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';

void main() {
  group('TelemetryService', () {
    test(
      'no-ops Crashlytics calls when Firebase is not ready, while buffering breadcrumbs',
      () async {
        var logCalls = 0;
        var keyCalls = 0;
        var errorCalls = 0;
        final telemetry = TelemetryService(
          isFirebaseReady: () => false,
          log: (_) async => logCalls++,
          setCustomKey: (_, _) async => keyCalls++,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) async => errorCalls++,
        );

        await telemetry.setCustomKey('auth_mode', 'local_only');
        await telemetry.logBreadcrumb('sync.interrupted_wipe_resumed');
        await telemetry.recordNonFatal(
          StateError('unexpected'),
          StackTrace.current,
          context: 'sync.sync_now',
          skipIfOffline: false,
        );

        expect(logCalls, 0);
        expect(keyCalls, 0);
        expect(errorCalls, 0);
        expect(telemetry.recentBreadcrumbs, [
          'sync.interrupted_wipe_resumed',
          'sync.sync_now error=StateError',
        ]);
      },
    );

    test('swallows errors thrown by Crashlytics callbacks', () async {
      final telemetry = TelemetryService(
        isFirebaseReady: () => true,
        log: (_) async => throw StateError('channel broken'),
        setCustomKey: (_, _) async => throw StateError('channel broken'),
        recordError:
            (
              error,
              stack, {
              required String reason,
              required Iterable<Object> information,
              required bool fatal,
            }) async => throw StateError('channel broken'),
      );

      await expectLater(
        telemetry.setCustomKey('auth_mode', 'signed_in'),
        completes,
      );
      await expectLater(telemetry.logBreadcrumb('sync.test'), completes);
      await expectLater(
        telemetry.recordNonFatal(
          StateError('boom'),
          StackTrace.current,
          context: 'sync.test',
        ),
        completes,
      );
    });

    test(
      'sanitizes custom keys and string values while preserving primitives',
      () async {
        final keys = <String, Object>{};
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          setCustomKey: (k, v) => keys[k] = v,
        );

        await telemetry.setCustomKey('firebase_ready', true);
        await telemetry.setCustomKey('photos_repaired_count', 7);
        await telemetry.setCustomKey('auth_mode', 'signed_in');
        await telemetry.setCustomKey('unsafe_email', 'potter@example.com');
        await telemetry.setCustomKey('bad/key', '/var/mobile/photo.jpg');

        expect(keys['firebase_ready'], isTrue);
        expect(keys['photos_repaired_count'], 7);
        expect(keys['auth_mode'], 'signed_in');
        expect(keys['unsafe_email'], 'redacted');
        expect(keys['redacted'], 'redacted');
      },
    );

    test(
      'maintains bounded FIFO ring buffer and attaches recent breadcrumbs to non-fatal reports',
      () async {
        final capturedInfo = <List<Object>>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                capturedInfo.add(information.toList());
              },
          maxBufferSize: 3,
        );

        await telemetry.logBreadcrumb('step.one');
        await telemetry.logBreadcrumb('step.two');
        await telemetry.logBreadcrumb('step.three');
        await telemetry.logBreadcrumb('step.four');

        expect(telemetry.recentBreadcrumbs, [
          'step.two',
          'step.three',
          'step.four',
        ]);

        await telemetry.recordNonFatal(
          StateError('boom'),
          StackTrace.current,
          context: 'sync.pull',
        );

        expect(capturedInfo, hasLength(1));
        expect(capturedInfo.single, [
          'step.three',
          'step.four',
          'sync.pull error=StateError',
        ]);
      },
    );

    test('skips routine offline errors by default', () async {
      final recorded = <String>[];
      final telemetry = TelemetryService(
        isFirebaseReady: () => true,
        log: recorded.add,
        recordError:
            (
              error,
              stack, {
              required String reason,
              required Iterable<Object> information,
              required bool fatal,
            }) async {
              recorded.add(error.toString());
            },
      );

      final offlineErrors = <Object>[
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        FirebaseAuthException(code: 'network-request-failed'),
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'retry-limit-exceeded',
        ),
        const SocketException('Failed host lookup'),
        TimeoutException('timed out'),
        SignOutIncompleteException(
          FirebaseAuthException(code: 'network-request-failed'),
        ),
      ];

      for (final err in offlineErrors) {
        await telemetry.recordNonFatal(
          err,
          StackTrace.current,
          context: 'sync.sync_now',
        );
      }

      expect(recorded, isEmpty);
    });

    test('sanitizes PII, filenames, tokens, and UIDs out of reports', () async {
      final logs = <String>[];
      final errors = <(Object, String, bool)>[];
      final telemetry = TelemetryService(
        isFirebaseReady: () => true,
        log: logs.add,
        recordError:
            (
              error,
              stack, {
              required String reason,
              required Iterable<Object> information,
              required bool fatal,
            }) async {
              errors.add((error, reason, fatal));
            },
      );

      final cases = <(String, Object, String)>[
        (
          'sync.wipe_failed',
          LocalPhotoWipeException(
            const FileSystemException(
              'Cannot delete /var/mobile/Documents/photos/piece-9/mug.jpg',
              '/var/mobile/Documents/photos/piece-9/mug.jpg',
              OSError('Permission denied', 13),
            ),
          ),
          'LocalPhotoWipeException(FileSystemException(errno=13))',
        ),
        (
          'sync.cloud_photo_delete',
          FirebaseException(
            plugin: 'firebase_storage',
            code: 'unauthorized',
            message:
                'uid=user-secret-99 email=potter@example.com token=ya29.secret users/user-secret-99/photos/p1/p2.jpg',
          ),
          'FirebaseException(plugin=firebase_storage, code=unauthorized)',
        ),
        (
          'auth.sign_out',
          PlatformException(
            code: 'sign_in_failed',
            message: 'Bearer eyJhbGciOi.secret.jwt alice@example.com',
            details: '/Users/alice/keychain.db',
          ),
          'PlatformException(code=sign_in_failed)',
        ),
        (
          'sync.wipe_failed',
          LocalDeviceNotSecuredException([
            StateError('sqlcipher-key-deadbeefcafe'),
          ]),
          'LocalDeviceNotSecuredException(StateError)',
        ),
        (
          'auth.refresh_providers_sign_out',
          SignOutIncompleteException(
            FirebaseAuthException(
              code: 'internal-error',
              message: 'uid=user-secret-99',
            ),
          ),
          'SignOutIncompleteException(FirebaseAuthException(plugin=firebase_auth, code=internal-error))',
        ),
        (
          'feedback.submit',
          Exception('Feedback from bob@example.com: my mug cracked'),
          '_Exception',
        ),
      ];

      for (final (context, err, expectedSummary) in cases) {
        logs.clear();
        errors.clear();
        await telemetry.recordNonFatal(
          err,
          StackTrace.current,
          context: context,
          attributes: {
            'unsafe_attr': 'bob@example.com',
            'operation': 'deletePhoto',
          },
          skipIfOffline: false,
        );

        expect(logs, hasLength(1));
        expect(errors, hasLength(1));
        final (recordedError, reason, fatal) = errors.single;
        expect(recordedError, isA<SanitizedTelemetryError>());
        expect(recordedError.toString(), '$context: $expectedSummary');
        expect(reason, context);
        expect(fatal, isFalse);

        final combined = '${logs.single} $recordedError';
        for (final forbidden in [
          'mug.jpg',
          '/var/mobile',
          'user-secret-99',
          'potter@example.com',
          'ya29.secret',
          'eyJhbGciOi',
          'alice@example.com',
          'keychain.db',
          'deadbeefcafe',
          'bob@example.com',
          'my mug cracked',
        ]) {
          expect(combined, isNot(contains(forbidden)));
        }
        expect(logs.single, contains('unsafe_attr=redacted'));
        expect(logs.single, contains('operation=deletePhoto'));
      }
    });

    test(
      'logBreadcrumb preserves structured describeError summaries while stripping PII',
      () async {
        final logs = <String>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: logs.add,
        );

        final cases = <(Object, String)>[
          (
            FirebaseException(
              plugin: 'firebase_auth',
              code: 'network-request-failed',
              message: 'uid=user-secret-99 potter@example.com',
            ),
            'FirebaseException(plugin=firebase_auth, code=network-request-failed)',
          ),
          (
            PlatformException(
              code: 'sign_in_failed',
              message: 'Bearer eyJhbGciOi.secret',
              details: '/Users/alice/keychain.db',
            ),
            'PlatformException(code=sign_in_failed)',
          ),
          (
            const FileSystemException(
              'Cannot open /var/mobile/Documents/photos/p1/mug.jpg',
              '/var/mobile/Documents/photos/p1/mug.jpg',
              OSError('Permission denied', 13),
            ),
            'FileSystemException(errno=13)',
          ),
          (
            LocalPhotoWipeException(
              const FileSystemException(
                'Cannot delete /var/mobile/mug.jpg',
                '/var/mobile/mug.jpg',
                OSError('EACCES', 13),
              ),
            ),
            'LocalPhotoWipeException(FileSystemException(errno=13))',
          ),
        ];

        for (final (err, expectedSummary) in cases) {
          logs.clear();
          await telemetry.logBreadcrumb(
            'sync.rekey_step_failed',
            attributes: {'step': 'rekey', 'unsafe': 'potter@example.com'},
            error: err,
          );

          expect(logs, hasLength(1));
          expect(
            logs.single,
            'sync.rekey_step_failed step=rekey unsafe=redacted error=$expectedSummary',
          );
          expect(telemetry.recentBreadcrumbs.last, logs.single);
          for (final forbidden in [
            'user-secret-99',
            'potter@example.com',
            'eyJhbGciOi',
            'keychain.db',
            '/var/mobile',
            'mug.jpg',
          ]) {
            expect(logs.single, isNot(contains(forbidden)));
          }
        }
      },
    );
  });
}
