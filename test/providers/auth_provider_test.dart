import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  group('AuthState', () {
    test('default status is unknown', () {
      const state = AuthState();
      expect(state.status, AuthStatus.unknown);
    });

    test('isSignedIn requires authenticated + uid', () {
      const noUid = AuthState(status: AuthStatus.authenticated);
      expect(noUid.isSignedIn, false);

      const withUid = AuthState(status: AuthStatus.authenticated, uid: 'u1');
      expect(withUid.isSignedIn, true);
    });

    test('isLocalOnly requires authenticated + no uid', () {
      const local = AuthState(status: AuthStatus.authenticated);
      expect(local.isLocalOnly, true);

      const withUid = AuthState(status: AuthStatus.authenticated, uid: 'u1');
      expect(withUid.isLocalOnly, false);
    });

    test('provider helpers check linkedProviders set', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        linkedProviders: {'google.com'},
      );
      expect(state.isGoogleLinked, true);
      expect(state.isAppleLinked, false);
    });
  });

  group('AuthNotifier.withState', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state is unknown before init completes', () {
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.unknown),
      );
      expect(notifier.debugState.status, AuthStatus.unknown);
    });

    test('skip sets authenticated with no uid', () async {
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.unauthenticated),
      );
      await notifier.skip();
      expect(notifier.debugState.status, AuthStatus.authenticated);
      expect(notifier.debugState.uid, isNull);
    });

    test('signOut sets unauthenticated and clears onboarding', () async {
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.authenticated),
      );
      await notifier.signOut();
      expect(notifier.debugState.status, AuthStatus.unauthenticated);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hasCompletedOnboarding'), false);
    });

    test('signOut publishes nothing while Firebase still holds the session, '
        'so the next launch cannot quietly restore it', () async {
      SharedPreferences.setMockInitialValues({'hasCompletedOnboarding': true});
      const signedIn = AuthState(
        status: AuthStatus.authenticated,
        uid: 'user-a',
      );
      var attempts = 0;
      final notifier = AuthNotifier.withState(
        signedIn,
        endFirebaseSession: () async {
          attempts++;
          throw SignOutIncompleteException(Exception('keychain locked'));
        },
      );

      await expectLater(
        notifier.signOut(),
        throwsA(isA<SignOutIncompleteException>()),
      );

      expect(attempts, 1);
      expect(published(notifier).status, AuthStatus.authenticated);
      expect(published(notifier).uid, 'user-a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hasCompletedOnboarding'), true);
    });

    test('signOut publishes unauthenticated once the session is confirmed '
        'gone', () async {
      var ended = false;
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.authenticated, uid: 'user-a'),
        endFirebaseSession: () async => ended = true,
      );

      await notifier.signOut();

      expect(ended, isTrue);
      expect(published(notifier).status, AuthStatus.unauthenticated);
    });
  });

  group('AuthNotifier telemetry', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'skips telemetry when reload fails with an offline TimeoutException',
      () async {
        final auth = _MockFirebaseAuth();
        final user = _MockUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.reload()).thenThrow(TimeoutException('offline'));
        when(() => auth.signOut()).thenAnswer((_) async {});

        var recorded = 0;
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) async {},
          recordError:
              (
                error,
                stack, {
                required String reason,
                required bool fatal,
              }) async {
                recorded++;
              },
        );

        final notifier = AuthNotifier(telemetry: telemetry, firebaseAuth: auth);
        addTearDown(notifier.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(recorded, 0);
      },
    );

    test(
      'records sanitized non-fatal error when reload fails unexpectedly',
      () async {
        final auth = _MockFirebaseAuth();
        final user = _MockUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.reload()).thenThrow(
          FirebaseAuthException(
            code: 'internal-error',
            message: 'uid=user-a email=potter@example.com',
          ),
        );
        when(() => auth.signOut()).thenAnswer((_) async {});

        final recorded = <(Object, String, bool)>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) async {},
          recordError:
              (
                error,
                stack, {
                required String reason,
                required bool fatal,
              }) async {
                recorded.add((error, reason, fatal));
              },
        );

        final notifier = AuthNotifier(telemetry: telemetry, firebaseAuth: auth);
        addTearDown(notifier.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(recorded, hasLength(1));
        expect(recorded.single.$2, 'auth.reload');
        expect(recorded.single.$3, isFalse);
        expect(
          recorded.single.$1.toString(),
          'auth.reload: FirebaseAuthException(plugin=firebase_auth, code=internal-error)',
        );
        expect(recorded.single.$1.toString(), isNot(contains('user-a')));
        expect(
          recorded.single.$1.toString(),
          isNot(contains('potter@example.com')),
        );
      },
    );

    test(
      'records sanitized non-fatal error when Firebase signOut throws',
      () async {
        final auth = _MockFirebaseAuth();
        final user = _MockUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => auth.signOut()).thenThrow(
          FirebaseAuthException(
            code: 'internal-error',
            message: 'token=secret-token',
          ),
        );

        final recorded = <(Object, String, bool)>[];
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) async {},
          recordError:
              (
                error,
                stack, {
                required String reason,
                required bool fatal,
              }) async {
                recorded.add((error, reason, fatal));
              },
        );

        final notifier = AuthNotifier.withState(
          const AuthState(status: AuthStatus.authenticated, uid: 'user-a'),
          telemetry: telemetry,
          firebaseAuth: auth,
        );
        addTearDown(notifier.dispose);

        await expectLater(
          notifier.signOut(),
          throwsA(isA<SignOutIncompleteException>()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(recorded, hasLength(1));
        expect(recorded.single.$2, 'auth.sign_out');
        expect(recorded.single.$3, isFalse);
        expect(recorded.single.$1.toString(), isNot(contains('secret-token')));
      },
    );
  });
}

/// What [notifier] currently publishes, read the way a listener sees it.
AuthState published(AuthNotifier notifier) {
  late AuthState current;
  notifier.addListener((state) => current = state)();
  return current;
}
