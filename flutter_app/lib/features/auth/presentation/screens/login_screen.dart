import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/shared/shared.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleEmailAuth() async {
    setState(() => _isLoading = true);
    try {
      final authService = ref.read(authServiceProvider);
      if (_isSignUp) {
        await authService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await authService.signInWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } on AuthException catch (e) {
      if (e.type != AuthErrorType.cancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).signInWithApple();
    } on AuthException catch (e) {
      if (e.type != AuthErrorType.cancelled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SwappTokens.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sticker Swapp',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: SwappTokens.spacingXxl),

                // Email field
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: SwappTokens.spacingMd),

                // Password field
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outlined),
                  ),
                ),
                const SizedBox(height: SwappTokens.spacingLg),

                // Email sign-in / sign-up button
                SwappButton(
                  label: _isSignUp ? 'Sign Up' : 'Sign In',
                  onPressed: _handleEmailAuth,
                  isLoading: _isLoading,
                  isExpanded: true,
                ),
                const SizedBox(height: SwappTokens.spacingSm),

                // Toggle sign-in / sign-up
                TextButton(
                  onPressed: () => setState(() => _isSignUp = !_isSignUp),
                  child: Text(
                    _isSignUp
                        ? 'Already have an account? Sign In'
                        : 'Need an account? Sign Up',
                  ),
                ),

                const SizedBox(height: SwappTokens.spacingLg),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SwappTokens.spacingMd,
                      ),
                      child: Text(
                        'or continue with',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: SwappTokens.spacingLg),

                // Google Sign-In
                SwappButton(
                  label: 'Continue with Google',
                  variant: SwappButtonVariant.outlined,
                  onPressed: _handleGoogleSignIn,
                  isExpanded: true,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: SwappTokens.spacingMd),

                // Apple Sign-In (iOS only per Apple guidelines)
                if (Platform.isIOS)
                  SwappButton(
                    label: 'Continue with Apple',
                    variant: SwappButtonVariant.outlined,
                    onPressed: _handleAppleSignIn,
                    isExpanded: true,
                    isLoading: _isLoading,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
