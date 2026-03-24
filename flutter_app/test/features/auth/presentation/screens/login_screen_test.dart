import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthState, AuthException;
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/features/auth/presentation/screens/login_screen.dart';
import 'package:flutter_app/shared/shared.dart';

// ── Helpers ───────────────────────────────────────────────────────────────

/// Wraps [LoginScreen] in the minimum widget tree required for testing.
Widget _buildSubject({_FakeAuthService? fakeService}) {
  return ProviderScope(
    overrides: [
      authServiceProvider
          .overrideWithValue(fakeService ?? _FakeAuthService()),
    ],
    child: MaterialApp(
      theme: SwappTheme.light,
      home: const LoginScreen(),
    ),
  );
}

// ── Fake AuthService ──────────────────────────────────────────────────────

/// Minimal fake that records calls without touching Supabase.
class _FakeAuthService extends AuthService {
  _FakeAuthService()
      : super(
          client: SupabaseClient(
            'https://fake.supabase.co',
            'fake-anon-key',
            authOptions:
                const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  bool signInCalled = false;
  bool signUpCalled = false;
  bool resetPasswordCalled = false;
  AuthException? errorToThrow;

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    signInCalled = true;
    if (errorToThrow != null) throw errorToThrow!;
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    signUpCalled = true;
    if (errorToThrow != null) throw errorToThrow!;
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<void> resetPassword(String email) async {
    resetPasswordCalled = true;
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<AuthResponse> signInWithGoogle() async {
    if (errorToThrow != null) throw errorToThrow!;
    return AuthResponse(session: null, user: null);
  }

  @override
  Future<AuthResponse> signInWithApple() async {
    if (errorToThrow != null) throw errorToThrow!;
    return AuthResponse(session: null, user: null);
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('LoginScreen', () {
    // ── Rendering ──

    testWidgets('renders title, email field, password field, and sign-in button',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Sticker Swapp'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('renders Google sign-in button', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Continue with Google'), findsOneWidget);
    });

    testWidgets('renders guest mode option', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Continue as Guest'), findsOneWidget);
    });

    testWidgets('renders or-continue-with divider', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('or continue with'), findsOneWidget);
    });

    testWidgets('renders forgot password link in sign-in mode', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Forgot password?'), findsOneWidget);
    });

    // ── Sign In / Sign Up Toggle ──

    testWidgets('toggles to sign-up mode when tapped', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Initially in sign-in mode
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.text('Need an account? Sign Up'), findsOneWidget);

      // Toggle to sign-up
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.text('Already have an account? Sign In'), findsOneWidget);
    });

    testWidgets('shows display name field in sign-up mode', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Not visible in sign-in mode
      expect(find.text('Display Name'), findsNothing);

      // Toggle to sign-up
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Display Name'), findsOneWidget);
    });

    testWidgets('hides forgot password in sign-up mode', (tester) async {
      await tester.pumpWidget(_buildSubject());

      expect(find.text('Forgot password?'), findsOneWidget);

      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      expect(find.text('Forgot password?'), findsNothing);
    });

    testWidgets('toggles back to sign-in mode', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Toggle to sign-up
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();
      expect(find.text('Sign Up'), findsOneWidget);

      // Toggle back to sign-in
      await tester.tap(find.text('Already have an account? Sign In'));
      await tester.pumpAndSettle();
      expect(find.text('Sign In'), findsOneWidget);
    });

    // ── Password Visibility ──

    testWidgets('toggles password visibility', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Initially obscured — visibility_outlined icon is shown
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

      // Tap the toggle
      await tester.tap(find.byIcon(Icons.visibility_outlined));
      await tester.pumpAndSettle();

      // Now visible — visibility_off icon is shown
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });

    // ── Form Validation ──

    testWidgets('shows validation error for empty email', (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Tap Sign In with empty fields
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Email is required'), findsOneWidget);
    });

    testWidgets('shows validation error for invalid email format',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'not-an-email',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });

    testWidgets('shows validation error for empty password', (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('shows validation error for short password in sign-up mode',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      // Switch to sign-up mode
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        '12345',
      );
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password must be at least 6 characters'),
        findsOneWidget,
      );
    });

    testWidgets('accepts valid input and calls sign-in', (tester) async {
      final fakeService = _FakeAuthService();
      await tester.pumpWidget(_buildSubject(fakeService: fakeService));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(fakeService.signInCalled, isTrue);
      expect(fakeService.signUpCalled, isFalse);
    });

    testWidgets('calls sign-up when in sign-up mode', (tester) async {
      final fakeService = _FakeAuthService();
      await tester.pumpWidget(_buildSubject(fakeService: fakeService));

      // Switch to sign-up
      await tester.tap(find.text('Need an account? Sign Up'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'new@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.tap(find.text('Sign Up'));
      await tester.pumpAndSettle();

      expect(fakeService.signUpCalled, isTrue);
      expect(fakeService.signInCalled, isFalse);
    });

    // ── Error Display ──

    testWidgets('shows snackbar on auth error', (tester) async {
      final fakeService = _FakeAuthService()
        ..errorToThrow = const AuthException(
          AuthErrorType.invalidCredentials,
          'Invalid login credentials',
        );

      await tester.pumpWidget(_buildSubject(fakeService: fakeService));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrongpassword',
      );
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Invalid login credentials'), findsOneWidget);
    });

    // ── Forgot Password ──

    testWidgets('forgot password shows error when email is empty',
        (tester) async {
      await tester.pumpWidget(_buildSubject());

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email address first'), findsOneWidget);
    });

    testWidgets('forgot password calls reset when email is provided',
        (tester) async {
      final fakeService = _FakeAuthService();
      await tester.pumpWidget(_buildSubject(fakeService: fakeService));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'user@example.com',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(fakeService.resetPasswordCalled, isTrue);
      expect(find.text('Password reset email sent'), findsOneWidget);
    });
  });
}
