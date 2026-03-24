import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/shared/shared.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  // Per-method loading states so individual buttons don't interfere.
  bool _emailLoading = false;
  bool _googleLoading = false;
  bool _appleLoading = false;

  bool get _anyLoading => _emailLoading || _googleLoading || _appleLoading;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  // ── Email/Password ──────────────────────────────────────────────────

  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _emailLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      if (_isSignUp) {
        final name = _displayNameController.text.trim();
        await authService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: name.isNotEmpty ? name : null,
        );
      } else {
        await authService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  // ── Google ──────────────────────────────────────────────────────────

  Future<void> _handleGoogleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on AuthException catch (e) {
      if (e.type != AuthErrorType.cancelled && mounted) {
        _showError(e.message);
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  // ── Apple ───────────────────────────────────────────────────────────

  Future<void> _handleAppleSignIn() async {
    setState(() => _appleLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } on AuthException catch (e) {
      if (e.type != AuthErrorType.cancelled && mounted) {
        _showError(e.message);
      }
    } finally {
      if (mounted) setState(() => _appleLoading = false);
    }
  }

  // ── Forgot Password ────────────────────────────────────────────────

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Enter your email address first');
      return;
    }

    try {
      await ref.read(authServiceProvider).resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent')),
        );
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SwappTokens.spacingXl),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Title ──
                  Text(
                    'Sticker Swapp',
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: SwappTokens.spacing3xl),

                  // ── Display Name (sign-up only) ──
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _displayNameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                    ),
                    const SizedBox(height: SwappTokens.spacingMd),
                  ],

                  // ── Email ──
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(value.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: SwappTokens.spacingMd),

                  // ── Password ──
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: _isSignUp
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (_isSignUp && value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) => _handleEmailAuth(),
                  ),
                  const SizedBox(height: SwappTokens.spacingLg),

                  // ── Sign In / Sign Up button ──
                  SwappButton(
                    label: _isSignUp ? 'Sign Up' : 'Sign In',
                    onPressed: _anyLoading ? null : _handleEmailAuth,
                    isLoading: _emailLoading,
                    isExpanded: true,
                  ),
                  const SizedBox(height: SwappTokens.spacingSm),

                  // ── Toggle + Forgot Password row ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _anyLoading
                            ? null
                            : () => setState(() {
                                  _isSignUp = !_isSignUp;
                                  _formKey.currentState?.reset();
                                }),
                        child: Text(
                          _isSignUp
                              ? 'Already have an account? Sign In'
                              : 'Need an account? Sign Up',
                        ),
                      ),
                    ],
                  ),
                  if (!_isSignUp) ...[
                    TextButton(
                      onPressed: _anyLoading ? null : _handleForgotPassword,
                      child: const Text('Forgot password?'),
                    ),
                  ],

                  const SizedBox(height: SwappTokens.spacingLg),

                  // ── Divider ──
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SwappTokens.spacingMd,
                        ),
                        child: Text(
                          'or continue with',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: SwappTokens.spacingLg),

                  // ── Google Sign-In ──
                  SwappButton(
                    label: 'Continue with Google',
                    variant: SwappButtonVariant.outlined,
                    onPressed: _anyLoading ? null : _handleGoogleSignIn,
                    isExpanded: true,
                    isLoading: _googleLoading,
                  ),
                  const SizedBox(height: SwappTokens.spacingMd),

                  // ── Apple Sign-In (iOS only) ──
                  if (defaultTargetPlatform == TargetPlatform.iOS)
                    SwappButton(
                      label: 'Continue with Apple',
                      variant: SwappButtonVariant.outlined,
                      onPressed: _anyLoading ? null : _handleAppleSignIn,
                      isExpanded: true,
                      isLoading: _appleLoading,
                    ),

                  const SizedBox(height: SwappTokens.spacingXxl),

                  // ── Guest mode ──
                  TextButton(
                    onPressed: _anyLoading ? null : () => context.go('/catalog'),
                    child: const Text('Continue as Guest'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
