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
  /// Age verification is handled separately via [verifyAge] after signup.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      return await _client.auth.signUp(
        email: email,
        password: password,
        data: {
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

  // ── Age Verification ─────────────────────────────────────────────

  /// Verify the user's age via server-side RPC.
  ///
  /// Calls `verify_age()` which calculates `is_under_13` on the server
  /// (prevents client-side tampering) and stamps `age_verified_at`.
  /// Also updates user metadata so the JWT reflects the verified state.
  /// Throws [AuthException] if already verified or on failure.
  Future<bool> verifyAge(DateTime dateOfBirth) async {
    try {
      final dobString =
          '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

      final isUnder13 = await _client.rpc(
        'verify_age',
        params: {'p_date_of_birth': dobString},
      ) as bool;

      // Mirror to user metadata so the router and Go middleware can read
      // the flags from the JWT without an extra DB query.
      await _client.auth.updateUser(
        UserAttributes(data: {
          'is_under_13': isUnder13,
          'date_of_birth': dobString,
          'age_verified_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );

      return isUnder13;
    } on PostgrestException catch (e) {
      throw AuthException(AuthErrorType.unknown, e.message);
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  // ── Parental Consent ─────────────────────────────────────────────

  /// Request parental consent by providing the parent's email.
  ///
  /// Calls `request_parental_consent()` RPC to generate a secure token,
  /// then invokes the `send-consent-email` Edge Function to email the parent.
  /// Updates user metadata with `parent_email` and `consent_requested_at`.
  Future<void> requestParentalConsent({required String parentEmail}) async {
    try {
      final token = await _client.rpc(
        'request_parental_consent',
        params: {'p_parent_email': parentEmail},
      ) as String;

      final displayName =
          _client.auth.currentUser?.userMetadata?['display_name'] as String? ??
              _client.auth.currentUser?.userMetadata?['full_name'] as String? ??
              'Your child';

      await _client.functions.invoke(
        'send-consent-email',
        body: {
          'parent_email': parentEmail,
          'token': token,
          'child_display_name': displayName,
        },
      );

      await _client.auth.updateUser(
        UserAttributes(data: {
          'parent_email': parentEmail,
          'consent_requested_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } on PostgrestException catch (e) {
      throw AuthException(AuthErrorType.unknown, e.message);
    } on FunctionException catch (e) {
      throw AuthException(
        AuthErrorType.unknown,
        e.details?.toString() ?? 'Failed to send consent email',
      );
    } catch (e) {
      throw AuthException(AuthErrorType.unknown, e.toString());
    }
  }

  /// Check if parental consent has been granted for the current user.
  Future<bool> checkParentalConsent() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _client
          .from('user_profiles')
          .select('parental_consent_at')
          .eq('user_id', userId)
          .single();

      return response['parental_consent_at'] != null;
    } catch (e) {
      return false;
    }
  }

  // ── Private Helpers ───────────────────────────────────────────────

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
