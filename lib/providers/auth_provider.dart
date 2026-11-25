import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/telemetry_service.dart';
import 'telemetry_provider.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

/// An explicit sign-out after which Firebase still holds the session. The
/// app stays signed in rather than claiming otherwise: a session Firebase
/// kept would be restored by the next launch's reload, so "signed out" would
/// be true only until then.
class SignOutIncompleteException implements Exception, TelemetryCauseCarrier {
  final Object? cause;

  SignOutIncompleteException(this.cause);

  @override
  Iterable<Object> get telemetryCauses => [?cause];

  @override
  String toString() => 'SignOutIncompleteException: $cause';
}

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
  AuthNotifier({
    TelemetryService? telemetry,
    @visibleForTesting FirebaseAuth? firebaseAuth,
  }) : _telemetry = telemetry ?? TelemetryService(),
       _firebaseAuth = firebaseAuth,
       _endFirebaseSessionOverride = null,
       super(const AuthState(status: AuthStatus.unknown)) {
    _init();
  }

  @visibleForTesting
  AuthNotifier.withState(
    super.initial, {
    Future<void> Function()? endFirebaseSession,
    TelemetryService? telemetry,
    FirebaseAuth? firebaseAuth,
  }) : _telemetry = telemetry ?? TelemetryService(),
       _firebaseAuth = firebaseAuth,
       _endFirebaseSessionOverride = endFirebaseSession;

  final TelemetryService _telemetry;
  final FirebaseAuth? _firebaseAuth;

  FirebaseAuth get _auth => _firebaseAuth ?? FirebaseAuth.instance;

  /// Optional test seam for ending the Firebase session.
  final Future<void> Function()? _endFirebaseSessionOverride;

  /// Ends the Firebase session, throwing [SignOutIncompleteException] unless
  /// it is confirmed gone.
  Future<void> _endFirebaseSession() =>
      (_endFirebaseSessionOverride ?? _signOutOfFirebase)();

  /// Firebase Auth error codes that prove the persisted session is permanently
  /// invalid and must be signed out. Transient offline, timeout, rate-limit,
  /// or backend errors are deliberately excluded so offline-first sync keeps
  /// the cached session and resumes automatically once connectivity returns.
  static const _permanentAuthInvalidationCodes = <String>{
    'user-disabled',
    'user-not-found',
    'user-token-expired',
    'invalid-user-token',
    'user-mismatch',
    'invalid-credential',
  };

  /// Set once the user has signed in or chosen to skip; a launch that finds
  /// it goes to the album rather than the sign-in screen. Public because the
  /// database bootstrap clears it when it discards a restored database, so
  /// that launch lands on sign-in — where a cloud user re-downloads.
  static const onboardingKey = 'hasCompletedOnboarding';

  static Set<String> _providerIds(User user) {
    return user.providerData.map((info) => info.providerId).toSet();
  }

  void _recordAuthMode(AuthState next) {
    final mode = next.isSignedIn
        ? 'signed_in'
        : next.isLocalOnly
        ? 'local_only'
        : 'signed_out';
    unawaited(_telemetry.setCustomKey('auth_mode', mode));
    unawaited(
      _telemetry.logBreadcrumb('auth.state', attributes: {'mode': mode}),
    );
  }

  Future<void> _init() async {
    try {
      // Check Firebase first — persisted session survives app restart
      User? firebaseUser;
      try {
        firebaseUser = _auth.currentUser;
      } catch (e) {
        debugPrint('AuthNotifier: Firebase not ready: $e');
        unawaited(_telemetry.logBreadcrumb('auth.firebase_not_ready'));
      }

      if (firebaseUser != null) {
        // Verify the token is still valid. Only sign out on permanent Firebase
        // Auth invalidation; preserve the cached session across transient
        // offline/timeout/network failures so sync resumes once online.
        try {
          await firebaseUser.reload().timeout(const Duration(seconds: 3));
        } catch (e, st) {
          final isPermanentInvalidation =
              e is FirebaseAuthException &&
              _permanentAuthInvalidationCodes.contains(e.code);
          if (isPermanentInvalidation) {
            debugPrint(
              'Firebase user permanently invalidated (${e.code}), signing out',
            );
            unawaited(
              _telemetry.setCustomKey(
                'auth_reload_outcome',
                'permanent_sign_out',
              ),
            );
            unawaited(
              _telemetry.recordNonFatal(
                e,
                st,
                context: 'auth.reload',
                attributes: {'code': e.code, 'outcome': 'permanent_sign_out'},
                skipIfOffline: false,
              ),
            );
            try {
              await _auth.signOut().timeout(const Duration(seconds: 3));
            } catch (signOutError, signOutStack) {
              unawaited(
                _telemetry.recordNonFatal(
                  signOutError,
                  signOutStack,
                  context: 'auth.reload_sign_out',
                ),
              );
            }
            final prefs = await SharedPreferences.getInstance();
            final completed = prefs.getBool(onboardingKey) ?? false;
            final next = completed
                ? const AuthState(status: AuthStatus.authenticated)
                : const AuthState(status: AuthStatus.unauthenticated);
            state = next;
            _recordAuthMode(next);
            return;
          }
          debugPrint(
            'Firebase user reload failed transiently, preserving cached session: $e',
          );
          unawaited(
            _telemetry.setCustomKey(
              'auth_reload_outcome',
              'transient_preserved',
            ),
          );
          unawaited(
            _telemetry.logBreadcrumb(
              'auth.reload_transient_preserved',
              error: e,
            ),
          );
          unawaited(_telemetry.recordNonFatal(e, st, context: 'auth.reload'));
          final cachedUser = _auth.currentUser ?? firebaseUser;
          final next = AuthState(
            status: AuthStatus.authenticated,
            displayName: cachedUser.displayName,
            uid: cachedUser.uid,
            linkedProviders: _providerIds(cachedUser),
          );
          state = next;
          _recordAuthMode(next);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(onboardingKey, true);
          return;
        }
        unawaited(_telemetry.setCustomKey('auth_reload_outcome', 'ok'));
        final currentUser = _auth.currentUser!;
        final next = AuthState(
          status: AuthStatus.authenticated,
          displayName: currentUser.displayName,
          uid: currentUser.uid,
          linkedProviders: _providerIds(currentUser),
        );
        state = next;
        _recordAuthMode(next);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(onboardingKey, true);
        return;
      }

      // No Firebase user — check if they skipped sign-in previously
      final prefs = await SharedPreferences.getInstance();
      final completed = prefs.getBool(onboardingKey) ?? false;
      final next = completed
          ? const AuthState(status: AuthStatus.authenticated)
          : const AuthState(status: AuthStatus.unauthenticated);
      state = next;
      _recordAuthMode(next);
    } catch (e, st) {
      debugPrint('Auth init failed: $e');
      unawaited(_telemetry.recordNonFatal(e, st, context: 'auth.init'));
      const next = AuthState(status: AuthStatus.unauthenticated);
      state = next;
      _recordAuthMode(next);
    }
  }

  Future<void> signIn(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, true);
    final next = AuthState(
      status: AuthStatus.authenticated,
      displayName: user.displayName,
      uid: user.uid,
      linkedProviders: _providerIds(user),
    );
    state = next;
    _recordAuthMode(next);
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, true);
    const next = AuthState(status: AuthStatus.authenticated);
    state = next;
    _recordAuthMode(next);
  }

  /// Signs out explicitly. Publishes unauthenticated only once Firebase no
  /// longer holds a session; otherwise throws [SignOutIncompleteException]
  /// and leaves the state alone, so the caller can say so and the user can
  /// try again.
  Future<void> signOut() async {
    await _endFirebaseSession();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardingKey, false);
    const next = AuthState(status: AuthStatus.unauthenticated);
    state = next;
    _recordAuthMode(next);
  }

  Future<void> _signOutOfFirebase() async {
    final FirebaseAuth auth;
    try {
      auth = _auth;
    } catch (e) {
      // Firebase never started, so it holds no session to restore.
      debugPrint('Firebase signOut skipped, Firebase is not ready: $e');
      return;
    }
    Object? failure;
    try {
      await auth.signOut();
    } catch (e, st) {
      debugPrint('Firebase signOut failed: $e');
      unawaited(_telemetry.recordNonFatal(e, st, context: 'auth.sign_out'));
      failure = e;
    }
    if (auth.currentUser != null) throw SignOutIncompleteException(failure);
  }

  Future<void> refreshProviders() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final providers = _providerIds(user);
    if (providers.isEmpty) {
      try {
        await signOut();
      } on SignOutIncompleteException catch (e, st) {
        // Nothing asked for this sign-out, so there is nobody to tell; the
        // next refresh tries again.
        debugPrint('AuthNotifier: $e');
        unawaited(
          _telemetry.recordNonFatal(
            e,
            st,
            context: 'auth.refresh_providers_sign_out',
          ),
        );
      }
      return;
    }
    state = AuthState(
      status: state.status,
      displayName: user.displayName ?? state.displayName,
      uid: user.uid,
      linkedProviders: providers,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(telemetry: ref.read(telemetryServiceProvider));
});

/// The Firebase/Google session handle. Lazily created, so nothing touches
/// FirebaseAuth until a screen actually asks for it, and overridable in tests.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());
