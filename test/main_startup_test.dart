import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/main.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';

void main() {
  group('initializeFirebaseServices', () {
    test(
      'falls back cleanly to offline mode when Firebase.initializeApp fails',
      () async {
        var firestoreConfigured = false;
        var appCheckActivated = false;
        var flutterHandlerSet = false;
        var platformHandlerSet = false;

        final ready = await initializeFirebaseServices(
          initializeApp: () async =>
              throw StateError('missing native Firebase config'),
          configureFirestore: () => firestoreConfigured = true,
          activateAppCheck: () async => appCheckActivated = true,
          setFlutterErrorHandler: (_) => flutterHandlerSet = true,
          setPlatformErrorHandler: (_) => platformHandlerSet = true,
        );

        expect(ready, isFalse);
        expect(firestoreConfigured, isFalse);
        expect(appCheckActivated, isFalse);
        expect(flutterHandlerSet, isFalse);
        expect(platformHandlerSet, isFalse);
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
}
