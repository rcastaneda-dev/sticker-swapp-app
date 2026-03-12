import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Typed auth error categories for presentation layer handling.
enum AuthErrorType {
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  userNotFound,
  networkError,
  cancelled,
  unknown,
}

class AuthException implements Exception {
  final AuthErrorType type;
  final String message;
  const AuthException(this.type, this.message);

  @override
  String toString() => 'AuthException($type): $message';
}

/// Auth service wrapping Supabase Auth with email, Google, and Apple sign-in.
///
/// All methods throw [AuthException] with typed errors for the presentation
/// layer to handle.
class AuthService {
  final SupabaseClient _client;

  AuthService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ── Email/Password ────────────────────────────────────────────────

  /// Sign up with email and password.
  /// Sets `is_under_13` in user_metadata based on the provided date of birth.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required DateTime dateOfBirth,
    String? displayName,
  }) async {
    try {
      final isUnder13 = _calculateIsUnder13(dateOfBirth);

      return await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'is_under_13': isUnder13,
          'date_of_birth': dateOfBirth.toIso8601String(),
          // ignore: use_null_aware_elements
          if (displayName != null) 'display_name': displayName,
        },
      );
    } on AuthApiException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  /// Sign in with email and password.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthApiException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  // ── Google Sign-In ────────────────────────────────────────────────

  /// Sign in with Google using native SDK + Supabase `signInWithIdToken`.
  ///
  /// `GOOGLE_WEB_CLIENT_ID` is the Web Client ID from Google Cloud Console,
  /// registered with Supabase as the OAuth provider client_id.
  /// `GOOGLE_IOS_CLIENT_ID` is the iOS client ID from GoogleService-Info.plist.
  Future<AuthResponse> signInWithGoogle() async {
    try {
      const webClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
      const iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

      final googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        clientId: iosClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException(
          AuthErrorType.cancelled,
          'Google sign-in cancelled',
        );
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw const AuthException(
          AuthErrorType.unknown,
          'Failed to obtain Google ID token',
        );
      }

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  // ── Apple Sign-In ─────────────────────────────────────────────────

  /// Sign in with Apple using native SDK + Supabase `signInWithIdToken`.
  ///
  /// Apple's OIDC flow requires a raw nonce in the authorization request
  /// and its SHA-256 hash for Supabase verification.
  Future<AuthResponse> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException(
          AuthErrorType.unknown,
          'Failed to obtain Apple ID token',
        );
      }

      return await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException(
          AuthErrorType.cancelled,
          'Apple sign-in cancelled',
        );
      }
      throw AuthException(AuthErrorType.unknown, e.message);
    } on AuthException {
      rethrow;
    } on AuthApiException catch (e) {
      throw _mapAuthError(e);
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  // ── Session Management ────────────────────────────────────────────

  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  Session? get currentSession => _client.auth.currentSession;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get onAuthStateChange =>
      _client.auth.onAuthStateChange;

  Future<void> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
    } on AuthApiException catch (e) {
      throw _mapAuthError(e);
    }
  }

  // ── Private Helpers ───────────────────────────────────────────────

  bool _calculateIsUnder13(DateTime dateOfBirth) {
    final now = DateTime.now();
    int age = now.year - dateOfBirth.year;
    if (now.month < dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day < dateOfBirth.day)) {
      age--;
    }
    return age < 13;
  }

  /// Cryptographically secure random nonce for Apple Sign-In.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  AuthException _mapAuthError(AuthApiException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid password')) {
      return AuthException(AuthErrorType.invalidCredentials, e.message);
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return AuthException(AuthErrorType.emailAlreadyInUse, e.message);
    }
    if (message.contains('weak password') ||
        message.contains('password should be')) {
      return AuthException(AuthErrorType.weakPassword, e.message);
    }
    if (message.contains('user not found')) {
      return AuthException(AuthErrorType.userNotFound, e.message);
    }
    return AuthException(AuthErrorType.unknown, e.message);
  }
}
