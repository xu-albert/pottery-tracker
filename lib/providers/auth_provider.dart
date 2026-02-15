import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final String? displayName;
  final String? uid;
  final Set<String> linkedProviders;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.displayName,
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
      : super(const AuthState(status: AuthStatus.unauthenticated)) {
    _init();
  }

  @visibleForTesting
  AuthNotifier.withState(super.initial);

  static const _onboardingKey = 'hasCompletedOnboarding';

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
            await FirebaseAuth.instance.signOut()
                .timeout(const Duration(seconds: 3));
          } catch (_) {}
          final prefs = await SharedPreferences.getInstance();
          final completed = prefs.getBool(_onboardingKey) ?? false;
          state = completed
              ? const AuthState(status: AuthStatus.authenticated)
              : const AuthState(status: AuthStatus.unauthenticated);
          return;
        }
        final currentUser = FirebaseAuth.instance.currentUser!;
        state = AuthState(
          status: AuthStatus.authenticated,
          displayName: currentUser.displayName,
          uid: currentUser.uid,
          linkedProviders: _providerIds(currentUser),
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_onboardingKey, true);
        return;
      }

      // No Firebase user — check if they skipped sign-in previously
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(_onboardingKey) ?? false;
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
    await prefs.setBool(_onboardingKey, true);
    state = AuthState(
      status: AuthStatus.authenticated,
      displayName: user.displayName,
      uid: user.uid,
      linkedProviders: _providerIds(user),
    );
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    state = const AuthState(status: AuthStatus.authenticated);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, false);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void refreshProviders() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    state = AuthState(
      status: state.status,
      displayName: user.displayName ?? state.displayName,
      uid: user.uid,
      linkedProviders: _providerIds(user),
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
