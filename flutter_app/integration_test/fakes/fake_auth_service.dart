import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_auth_state_notifier.dart';

/// Fake auth service that coordinates with [FakeAuthStateNotifier].
///
/// When [signUpWithEmail] or [signInWithEmail] is called (by LoginScreen),
/// it triggers [authNotifier.simulateSignIn] to drive the GoRouter redirects.
class FakeAuthService extends AuthService {
  final FakeAuthStateNotifier authNotifier;

  /// Whether verifyAge should return true (under-13).
  bool verifyAgeReturnsUnder13;

  /// Tracks calls for assertions.
  bool signUpCalled = false;
  bool signInCalled = false;
  bool verifyAgeCalled = false;
  bool requestConsentCalled = false;
  bool migrateInventoryCalled = false;

  FakeAuthService({
    required this.authNotifier,
    this.verifyAgeReturnsUnder13 = false,
  }) : super(client: _fakeSupabaseClient());

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    signUpCalled = true;
    // Simulate sign-in with no age verification yet
    authNotifier.simulateSignIn(metadata: {
      if (displayName != null) 'display_name': displayName,
    });
    return AuthResponse(
      session: null,
      user: null,
    );
  }

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signInCalled = true;
    authNotifier.simulateSignIn(metadata: {});
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<bool> verifyAge(DateTime dateOfBirth) async {
    verifyAgeCalled = true;
    final isUnder13 = verifyAgeReturnsUnder13;
    authNotifier.updateMetadata({
      'is_under_13': isUnder13,
      'date_of_birth':
          '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}',
      'age_verified_at': DateTime.now().toUtc().toIso8601String(),
    });
    return isUnder13;
  }

  @override
  Future<void> requestParentalConsent({required String parentEmail}) async {
    requestConsentCalled = true;
    // Don't update metadata yet — test will simulate consent separately
  }

  @override
  Future<bool> checkParentalConsent() async {
    // Return based on current auth state metadata
    return false;
  }

  @override
  Future<({int itemsSent, int itemsWritten, bool alreadyMigrated})>
      migrateGuestInventory({
    required String deviceUuid,
    required List<Map<String, dynamic>> items,
  }) async {
    migrateInventoryCalled = true;
    return (
      itemsSent: items.length,
      itemsWritten: items.length,
      alreadyMigrated: false,
    );
  }

  @override
  Future<void> signOut() async {
    authNotifier.simulateSignOut();
  }

  @override
  Future<void> resetPassword(String email) async {}

  /// Create a minimal SupabaseClient that won't hit real services.
  static SupabaseClient _fakeSupabaseClient() {
    return SupabaseClient(
      'https://fake.supabase.co',
      'fake-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
  }
}
