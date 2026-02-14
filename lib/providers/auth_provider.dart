import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final String? displayName;
  final String? uid;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.displayName,
    this.uid,
  });

  bool get isSignedIn => status == AuthStatus.authenticated && uid != null;
  bool get isLocalOnly => status == AuthStatus.authenticated && uid == null;
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  static const _onboardingKey = 'hasCompletedOnboarding';

  Future<void> _init() async {
    // Check Firebase first — persisted session survives app restart
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        displayName: firebaseUser.displayName,
        uid: firebaseUser.uid,
      );
      // Ensure onboarding flag is set
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
  }

  Future<void> signIn(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    state = AuthState(
      status: AuthStatus.authenticated,
      displayName: user.displayName,
      uid: user.uid,
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
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
