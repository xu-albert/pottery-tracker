import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final _googleSignIn = GoogleSignIn();

  Future<String?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      return account?.displayName;
    } catch (_) {
      return null;
    }
  }

  Future<String?> signInWithApple() async {
    // Phase 1: UI-only stub — no Firebase backend
    // In Phase 2, this will call sign_in_with_apple and Firebase Auth
    return 'Apple User';
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
