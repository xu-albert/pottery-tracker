import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/services/telemetry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockUserInfo extends Mock implements UserInfo {}

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
      expect(published(notifier).status, AuthStatus.unknown);
    });

    test('skip sets authenticated with no uid', () async {
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.unauthenticated),
      );
      await notifier.skip();
      expect(published(notifier).status, AuthStatus.authenticated);
      expect(published(notifier).uid, isNull);
    });

    test('signOut sets unauthenticated and clears onboarding', () async {
      final notifier = AuthNotifier.withState(
        const AuthState(status: AuthStatus.authenticated),
      );
      await notifier.signOut();
      expect(published(notifier).status, AuthStatus.unauthenticated);

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

  group('AuthNotifier._init reload resilience & telemetry', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({'hasCompletedOnboarding': true});
    });

    _MockUser mockCachedUser({
      String uid = 'user-a',
      String? displayName = 'Potter',
      List<String> providers = const ['apple.com'],
    }) {
      final user = _MockUser();
      when(() => user.uid).thenReturn(uid);
      when(() => user.displayName).thenReturn(displayName);
      final infos = [
        for (final id in providers)
          (() {
            final info = _MockUserInfo();
            when(() => info.providerId).thenReturn(id);
            return info;
          })(),
      ];
      when(() => user.providerData).thenReturn(infos);
      return user;
    }

    test(
      'preserves cached Firebase session and does NOT sign out on offline TimeoutException',
      () async {
        final auth = _MockFirebaseAuth();
        final user = mockCachedUser();
        when(() => auth.currentUser).thenReturn(user);
        when(() => user.reload()).thenThrow(TimeoutException('offline'));
        when(() => auth.signOut()).thenAnswer((_) async {});

        final keys = <String, Object>{};
        var recorded = 0;
        final telemetry = TelemetryService(
          isFirebaseReady: () => true,
          log: (_) async {},
          setCustomKey: (k, v) => keys[k] = v,
          recordError:
              (
                error,
                stack, {
                required String reason,
                required Iterable<Object> information,
                required bool fatal,
              }) async {
                recorded++;
              },
        );

        final notifier = AuthNotifier(telemetry: telemetry, firebaseAuth: auth);
        addTearDown(notifier.dispose);
        await Future<void>.delayed(Duration.zero);

        final state = published(notifier);
        expect(state.status, AuthStatus.authenticated);
        expect(state.isSignedIn, isTrue);
        expect(state.uid, 'user-a');
        expect(state.displayName, 'Potter');
        expect(state.isAppleLinked, isTrue);
        verifyNever(() => auth.signOut());
        expect(recorded, 0);
        expect(keys['auth_reload_outcome'], 'transient_preserved');
        expect(keys['auth_mode'], 'signed_in');
      },
    );

    test(
      'preserves cached Firebase session and does NOT sign out on network-request-failed',
      () async {
        final auth = _MockFirebaseAuth();
        final user = mockCachedUser(providers: const ['google.com']);
        when(() => auth.currentUser).thenReturn(user);
        when(
          () => user.reload(),
        ).thenThrow(FirebaseAuthException(code: 'network-request-failed'));
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
                required Iterable<Object> information,
                required bool fatal,
              }) async {
                recorded++;
              },
        );

        final notifier = AuthNotifier(telemetry: telemetry, firebaseAuth: auth);
        addTearDown(notifier.dispose);
        await Future<void>.delayed(Duration.zero);

        final state = published(notifier);
        expect(state.isSignedIn, isTrue);
        expect(state.uid, 'user-a');
        expect(state.isGoogleLinked, isTrue);
        verifyNever(() => auth.signOut());
        expect(recorded, 0);
      },
    );

    test(
      'preserves cached session and records sanitized non-fatal on unexpected transient reload error',
      () async {
        final auth = _MockFirebaseAuth();
        final user = mockCachedUser();
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
                required Iterable<Object> information,
                required bool fatal,
              }) async {
                recorded.add((error, reason, fatal));
              },
        );

        final notifier = AuthNotifier(telemetry: telemetry, firebaseAuth: auth);
        addTearDown(notifier.dispose);
        await Future<void>.delayed(Duration.zero);

        expect(published(notifier).isSignedIn, isTrue);
        expect(published(notifier).uid, 'user-a');
        verifyNever(() => auth.signOut());
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

    for (final code in const [
      'user-disabled',
      'user-not-found',
      'user-token-expired',
      'invalid-user-token',
      'user-mismatch',
      'invalid-credential',
    ]) {
      test(
        'signs out cleanly on permanent Firebase Auth invalidation ($code)',
        () async {
          final auth = _MockFirebaseAuth();
          final user = mockCachedUser();
          when(() => auth.currentUser).thenReturn(user);
          when(() => user.reload()).thenThrow(
            FirebaseAuthException(
              code: code,
              message: 'uid=user-a email=potter@example.com',
            ),
          );
          when(() => auth.signOut()).thenAnswer((_) async {});

          final keys = <String, Object>{};
          final recorded = <(Object, String, bool)>[];
          final telemetry = TelemetryService(
            isFirebaseReady: () => true,
            log: (_) async {},
            setCustomKey: (k, v) => keys[k] = v,
            recordError:
                (
                  error,
                  stack, {
                  required String reason,
                  required Iterable<Object> information,
                  required bool fatal,
                }) async {
                  recorded.add((error, reason, fatal));
                },
          );

          final notifier = AuthNotifier(
            telemetry: telemetry,
            firebaseAuth: auth,
          );
          addTearDown(notifier.dispose);
          await Future<void>.delayed(Duration.zero);

          final state = published(notifier);
          expect(state.status, AuthStatus.authenticated);
          expect(state.isLocalOnly, isTrue);
          expect(state.uid, isNull);
          verify(() => auth.signOut()).called(1);
          expect(keys['auth_reload_outcome'], 'permanent_sign_out');
          expect(keys['auth_mode'], 'local_only');
          expect(recorded, hasLength(1));
          expect(recorded.single.$2, 'auth.reload');
          expect(
            recorded.single.$1.toString(),
            'auth.reload: FirebaseAuthException(plugin=firebase_auth, code=$code)',
          );
          expect(recorded.single.$1.toString(), isNot(contains('user-a')));
        },
      );
    }

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
                required Iterable<Object> information,
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
