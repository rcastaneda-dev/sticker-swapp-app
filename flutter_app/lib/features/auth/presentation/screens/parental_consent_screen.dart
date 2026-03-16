import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/shared/shared.dart';

class ParentalConsentScreen extends ConsumerStatefulWidget {
  const ParentalConsentScreen({super.key});

  @override
  ConsumerState<ParentalConsentScreen> createState() =>
      _ParentalConsentScreenState();
}

class _ParentalConsentScreenState
    extends ConsumerState<ParentalConsentScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void initState() {
    super.initState();
    // If consent was already requested (user returns to this screen), show waiting state
    final authState = ref.read(authStateProvider);
    if (authState is AuthAuthenticated) {
      final requested =
          authState.user.userMetadata?['consent_requested_at'] != null;
      if (requested) {
        _emailSent = true;
        _emailController.text =
            authState.user.userMetadata?['parent_email'] as String? ?? '';
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  Future<void> _submitParentEmail() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authServiceProvider)
          .requestParentalConsent(parentEmail: email);
      if (mounted) {
        setState(() {
          _emailSent = true;
          _isLoading = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resendEmail() async {
    final email = _emailController.text.trim().isNotEmpty
        ? _emailController.text.trim()
        : _parentEmailFromMetadata();

    if (email == null || email.isEmpty) {
      setState(() => _emailSent = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authServiceProvider)
          .requestParentalConsent(parentEmail: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Consent email resent')),
        );
        setState(() => _isLoading = false);
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  String? _parentEmailFromMetadata() {
    final authState = ref.read(authStateProvider);
    if (authState is AuthAuthenticated) {
      return authState.user.userMetadata?['parent_email'] as String?;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Listen to polling provider for auto-detection of consent
    if (_emailSent) {
      ref.listen(consentPollingProvider, (_, next) {
        next.whenData((hasConsent) {
          if (hasConsent && mounted) {
            // Router will auto-redirect when authStateProvider updates
          }
        });
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SwappTokens.spacingXl),
            child: _emailSent ? _buildWaitingState() : _buildEmailInputState(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailInputState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.family_restroom_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Parent or Guardian Approval',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          'Since you are under 13, we need permission from your parent or '
          'guardian before you can use all features.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: "Parent's email address",
            hintText: 'parent@example.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        SwappButton(
          label: 'Send Consent Request',
          onPressed: _isLoading ? null : _submitParentEmail,
          isLoading: _isLoading,
          isExpanded: true,
        ),
      ],
    );
  }

  Widget _buildWaitingState() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Waiting for Approval',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          "We sent an email to your parent or guardian. Once they approve, "
          "you'll be able to use all features of Sticker Swapp.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: SwappTokens.spacingLg),
          child: CircularProgressIndicator(),
        ),
        Text(
          'Checking automatically...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        SwappButton(
          label: 'Resend Email',
          variant: SwappButtonVariant.outlined,
          onPressed: _isLoading ? null : _resendEmail,
          isLoading: _isLoading,
          isExpanded: true,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        TextButton(
          onPressed: () => setState(() => _emailSent = false),
          child: const Text('Use a different email'),
        ),
      ],
    );
  }
}
