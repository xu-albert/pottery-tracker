import 'package:drift/native.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/main.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/database_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';
import 'package:pottery_tracker/services/auth_service.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('initializeFirebaseServices', () {
    test(
      'falls back cleanly to offline mode when Firebase.initializeApp fails',
      () async {
        var firestoreConfigured = false;
        var appCheckActivated = false;
        var flutterHandlerSet = false;
        var platformHandlerSet = false;
        final telemetry = TelemetryService(isFirebaseReady: () => false);

        final ready = await initializeFirebaseServices(
          initializeApp: () async => throw FirebaseException(
            plugin: 'firebase_core',
            code: 'invalid-app-id',
            message: 'secret-config',
          ),
          configureFirestore: () => firestoreConfigured = true,
          activateAppCheck: () async => appCheckActivated = true,
          setFlutterErrorHandler: (_) => flutterHandlerSet = true,
          setPlatformErrorHandler: (_) => platformHandlerSet = true,
          telemetry: telemetry,
        );

        expect(ready, isFalse);
        expect(firestoreConfigured, isFalse);
        expect(appCheckActivated, isFalse);
        expect(flutterHandlerSet, isFalse);
        expect(platformHandlerSet, isFalse);
        expect(telemetry.recentBreadcrumbs, [
          'startup.firebase_init ready=false error=FirebaseException(plugin=firebase_core, code=invalid-app-id)',
        ]);
      },
    );

    test(
      'reports configureFirestore failure as non-fatal without logging ready=false',
      () async {
        var appCheckActivated = false;
        var flutterHandlerSet = false;
        var platformHandlerSet = false;
        final customKeys = <String, Object>{};
        final nonFatals = <(Object, String, bool)>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) {},
          setCustomKey: (k, v) => customKeys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) {
                nonFatals.add((error, reason, fatal));
              },
        );

        final ready = await initializeFirebaseServices(
          initializeApp: () async {},
          configureFirestore: () => throw StateError('settings locked'),
          activateAppCheck: () async => appCheckActivated = true,
          setFlutterErrorHandler: (_) => flutterHandlerSet = true,
          setPlatformErrorHandler: (_) => platformHandlerSet = true,
          recordFlutterFatalError: (_) {},
          recordError: (error, stack, {bool fatal = false}) async {},
          telemetry: telemetry,
        );
        await Future<void>.delayed(Duration.zero);

        expect(ready, isTrue);
        expect(appCheckActivated, isTrue);
        expect(flutterHandlerSet, isTrue);
        expect(platformHandlerSet, isTrue);
        expect(customKeys['firebase_ready'], isTrue);
        expect(
          telemetry.recentBreadcrumbs,
          contains('startup.firebase_init ready=true'),
        );
        expect(
          telemetry.recentBreadcrumbs.any((b) => b.contains('ready=false')),
          isFalse,
        );
        expect(nonFatals, hasLength(1));
        expect(
          nonFatals.single.$1.toString(),
          'startup.firestore_settings: StateError',
        );
        expect(nonFatals.single.$2, 'startup.firestore_settings');
        expect(nonFatals.single.$3, isFalse);
      },
    );

    test(
      'wires App Check and fatal Crashlytics handlers when Firebase initializes',
      () async {
        var firestoreConfigured = false;
        var appCheckActivated = false;
        FlutterExceptionHandler? installedFlutterHandler;
        bool Function(Object error, StackTrace stack)? installedPlatformHandler;
        final recordedErrors = <(Object, StackTrace, bool)>[];

        void fakeFlutterFatal(FlutterErrorDetails details) {}

        final ready = await initializeFirebaseServices(
          initializeApp: () async {},
          configureFirestore: () => firestoreConfigured = true,
          activateAppCheck: () async => appCheckActivated = true,
          setFlutterErrorHandler: (handler) =>
              installedFlutterHandler = handler,
          setPlatformErrorHandler: (handler) =>
              installedPlatformHandler = handler,
          recordFlutterFatalError: fakeFlutterFatal,
          recordError: (error, stack, {bool fatal = false}) async {
            recordedErrors.add((error, stack, fatal));
          },
        );

        expect(ready, isTrue);
        expect(firestoreConfigured, isTrue);
        expect(appCheckActivated, isTrue);
        expect(installedFlutterHandler, same(fakeFlutterFatal));
        expect(installedPlatformHandler, isNotNull);

        final error = StateError('uncaught async failure');
        final stack = StackTrace.current;
        final handled = installedPlatformHandler!(error, stack);
        await Future<void>.delayed(Duration.zero);

        expect(handled, isTrue);
        expect(recordedErrors, hasLength(1));
        expect(recordedErrors.single.$1, same(error));
        expect(recordedErrors.single.$2, same(stack));
        expect(recordedErrors.single.$3, isTrue);
      },
    );

    test(
      'still wires Crashlytics handlers when App Check activation fails',
      () async {
        bool Function(Object error, StackTrace stack)? installedPlatformHandler;
        var recordedFatal = false;

        final ready = await initializeFirebaseServices(
          initializeApp: () async {},
          configureFirestore: () {},
          activateAppCheck: () async => throw Exception('app check failed'),
          setFlutterErrorHandler: (_) {},
          setPlatformErrorHandler: (handler) =>
              installedPlatformHandler = handler,
          recordFlutterFatalError: (_) {},
          recordError: (error, stack, {bool fatal = false}) async {
            recordedFatal = fatal;
          },
        );

        expect(ready, isTrue);
        expect(installedPlatformHandler, isNotNull);
        expect(
          installedPlatformHandler!(Exception('boom'), StackTrace.current),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);
        expect(recordedFatal, isTrue);
      },
    );

    test(
      'platform error handler swallows Crashlytics recording failures',
      () async {
        bool Function(Object error, StackTrace stack)? installedPlatformHandler;

        await initializeFirebaseServices(
          initializeApp: () async {},
          configureFirestore: () {},
          activateAppCheck: () async {},
          setFlutterErrorHandler: (_) {},
          setPlatformErrorHandler: (handler) =>
              installedPlatformHandler = handler,
          recordFlutterFatalError: (_) {},
          recordError: (error, stack, {bool fatal = false}) async {
            throw StateError('crashlytics unavailable');
          },
        );

        expect(
          installedPlatformHandler!(Exception('boom'), StackTrace.current),
          isTrue,
        );
        await Future<void>.delayed(Duration.zero);
      },
    );
  });

  test('routerProvider builds offline without Firebase initialized', () {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            const AuthState(status: AuthStatus.authenticated),
          ),
        ),
        deviceLockedProvider.overrideWithValue(false),
        deviceStampedProvider.overrideWithValue(false),
      ],
    );
    addTearDown(container.dispose);

    expect(() => container.read(routerProvider), returnsNormally);
  });

  test(
    'syncStateProvider and AuthService construct offline without Firebase initialized',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authProvider.overrideWith(
            (_) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(syncStateProvider).status, SyncStatus.disabled);
      expect(() => AuthService(), returnsNormally);
      expect(() => container.read(authServiceProvider), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    },
  );
}
