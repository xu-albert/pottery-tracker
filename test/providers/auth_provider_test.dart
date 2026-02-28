import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  });
}
