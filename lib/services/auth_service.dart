import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class SignInCancelledException implements Exception {}

class AccountAlreadyLinkedException implements Exception {}

class AuthService {
  final _firebaseAuth = FirebaseAuth.instance;
  final _googleSignIn = GoogleSignIn();

  User? get currentUser => _firebaseAuth.currentUser;

  Future<AuthCredential> _getGoogleCredential() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      throw SignInCancelledException();
    }

    final googleAuth = await googleUser.authentication;
    return GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
  }

  Future<(OAuthCredential, AuthorizationCredentialAppleID)> _getAppleCredential() async {
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    final AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw SignInCancelledException();
      }
      rethrow;
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    return (oauthCredential, appleCredential);
  }

  Future<User> signInWithGoogle() async {
    final credential = await _getGoogleCredential();
    final userCredential =
        await _firebaseAuth.signInWithCredential(credential);
    return userCredential.user!;
  }

  Future<User> signInWithApple() async {
    final (oauthCredential, appleCredential) = await _getAppleCredential();
    final userCredential =
        await _firebaseAuth.signInWithCredential(oauthCredential);

    // Apple only returns the name on the first sign-in, so persist it
    final user = userCredential.user!;
    if (appleCredential.givenName != null && user.displayName == null) {
      final name =
          '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
              .trim();
      if (name.isNotEmpty) {
        await user.updateDisplayName(name);
        await user.reload();
        return _firebaseAuth.currentUser!;
      }
    }

    return user;
  }

  Future<void> linkGoogle() async {
    final credential = await _getGoogleCredential();
    try {
      await currentUser!.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw AccountAlreadyLinkedException();
      }
      rethrow;
    }
  }

  Future<void> linkApple() async {
    final (oauthCredential, _) = await _getAppleCredential();
    try {
      await currentUser!.linkWithCredential(oauthCredential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw AccountAlreadyLinkedException();
      }
      rethrow;
    }
  }

  Future<void> unlinkGoogle() async {
    await currentUser!.unlink('google.com');
  }

  Future<void> unlinkApple() async {
    await currentUser!.unlink('apple.com');
  }

  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    await _googleSignIn.signOut();
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }
}
