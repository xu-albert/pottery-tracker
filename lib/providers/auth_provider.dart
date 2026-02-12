import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthState {
  final AuthStatus status;
  final String? displayName;

  const AuthState({this.status = AuthStatus.unknown, this.displayName});

  AuthState copyWith({AuthStatus? status, String? displayName}) =>
      AuthState(
        status: status ?? this.status,
        displayName: displayName ?? this.displayName,
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  static const _onboardingKey = 'hasCompletedOnboarding';
  static const _nameKey = 'userName';

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_onboardingKey) ?? false;
    if (completed) {
      state = AuthState(
        status: AuthStatus.authenticated,
        displayName: prefs.getString(_nameKey),
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> signIn({String? displayName}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    if (displayName != null) await prefs.setString(_nameKey, displayName);
    state = AuthState(
      status: AuthStatus.authenticated,
      displayName: displayName,
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
    await prefs.remove(_nameKey);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
