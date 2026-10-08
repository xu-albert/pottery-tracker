import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// An explicit sign-out after which Firebase still holds the session. The
/// app stays signed in rather than claiming otherwise: a session Firebase
/// kept would be restored by the next launch's reload, so "signed out" would
/// be true only until then.
class SignOutIncompleteException implements Exception {
  final Object? cause;

  SignOutIncompleteException(this.cause);

  @override
  String toString() => 'SignOutIncompleteException: $cause';
}

class AuthState {
  final AuthStatus status;
  final String? displayName;

  /// Shown in place of [displayName] where the provider gave no name, as
  /// Apple does after the first sign-in.
  final String? email;
  final String? uid;
  final Set<String> linkedProviders;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.displayName,
    this.email,
    this.uid,
    this.linkedProviders = const {},
  });

  bool get isSignedIn => status == AuthStatus.authenticated && uid != null;
  bool get isLocalOnly => status == AuthStatus.authenticated && uid == null;
  bool get isGoogleLinked => linkedProviders.contains('google.com');
  bool get isAppleLinked => linkedProviders.contains('apple.com');
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier()
    : _endFirebaseSession = _signOutOfFirebase,
      super(const AuthState(status: AuthStatus.unknown)) {
    _init();
  }

  @visibleForTesting
  AuthNotifier.withState(
    super.initial, {
    Future<void> Function()? endFirebaseSession,
  }) : _endFirebaseSession = endFirebaseSession ?? _signOutOfFirebase;

  /// Ends the Firebase session, throwing [SignOutIncompleteException] unless
  /// it is confirmed gone.
  final Future<void> Function() _endFirebaseSession;

  /// Set once the user has signed in or chosen to skip; a launch that finds
  /// it goes to the album rather than the sign-in screen. Public because the
  /// database bootstrap clears it when it discards a restored database, so
  /// that launch lands on sign-in — where a cloud user re-downloads.
  static const onboardingKey = 'hasCompletedOnboarding';

  static Set<String> _providerIds(User user) {
    return user.providerData.map((info) => info.providerId).toSet();
  }

  Future<void> _init() async {
    try {
      // Check Firebase first — persisted session survives app restart
      User? firebaseUser;
      try {
        firebaseUser = FirebaseAuth.instance.currentUser;
      } catch (e) {
        debugPrint('AuthNotifier: Firebase not ready: $e');
      }

      if (firebaseUser != null) {
        // Verify the token is still valid
        try {
          await firebaseUser.reload().timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('Firebase user reload failed, signing out: $e');
          try {
            await FirebaseAuth.instance.signOut().timeout(
              const Duration(seconds: 3),
            );
          } catch (_) {}
          final prefs = await SharedPreferences.getInstance();
          final completed = prefs.getBool(onboardingKey) ?? false;
          state = completed
              ? const AuthState(status: AuthStatus.authenticated)
              : const AuthState(status: AuthStatus.unauthenticated);
          return;
        }
        final currentUser = FirebaseAuth.instance.currentUser!;
        state = AuthState(
          status: AuthStatus.authenticated,
          displayName: currentUser.displayName,
          email: currentUser.email,
          uid: currentUser.uid,
          linkedProviders: _providerIds(currentUser),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(onboardingKey, true);
        return;
      }

      // No Firebase user — check if they skipped sign-in previously
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(onboardingKey) ?? false;
      if (completed) {
        state = const AuthState(status: AuthStatus.authenticated);
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      debugPrint('Auth init failed: $e');
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> signIn(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, true);
    state = AuthState(
      status: AuthStatus.authenticated,
      displayName: user.displayName,
      email: user.email,
      uid: user.uid,
      linkedProviders: _providerIds(user),
    );
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, true);
    state = const AuthState(status: AuthStatus.authenticated);
  }

  /// Signs out explicitly. Publishes unauthenticated only once Firebase no
  /// longer holds a session; otherwise throws [SignOutIncompleteException]
  /// and leaves the state alone, so the caller can say so and the user can
  /// try again.
  Future<void> signOut() async {
    await _endFirebaseSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, false);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  static Future<void> _signOutOfFirebase() async {
    final FirebaseAuth auth;
    try {
      auth = FirebaseAuth.instance;
    } catch (e) {
      // Firebase never started, so it holds no session to restore.
      debugPrint('Firebase signOut skipped, Firebase is not ready: $e');
      return;
    }
    Object? failure;
    try {
      await auth.signOut();
    } catch (e) {
      debugPrint('Firebase signOut failed: $e');
      failure = e;
    }
    if (auth.currentUser != null) throw SignOutIncompleteException(failure);
  }

  Future<void> refreshProviders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final providers = _providerIds(user);
    if (providers.isEmpty) {
      try {
        await signOut();
      } on SignOutIncompleteException catch (e) {
        // Nothing asked for this sign-out, so there is nobody to tell; the
        // next refresh tries again.
        debugPrint('AuthNotifier: $e');
      }
      return;
    }
    state = AuthState(
      status: state.status,
      displayName: user.displayName ?? state.displayName,
      email: user.email ?? state.email,
      uid: user.uid,
      linkedProviders: providers,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// The Firebase/Google session handle. Lazily created, so nothing touches
/// FirebaseAuth until a screen actually asks for it, and overridable in tests.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
