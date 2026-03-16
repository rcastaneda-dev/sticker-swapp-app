import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/shared/shared.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

class AgeVerificationScreen extends ConsumerStatefulWidget {
  const AgeVerificationScreen({super.key});

  @override
  ConsumerState<AgeVerificationScreen> createState() =>
      _AgeVerificationScreenState();
}

class _AgeVerificationScreenState
    extends ConsumerState<AgeVerificationScreen> {
  DateTime? _selectedDate;
  bool _isLoading = false;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 13, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
      helpText: 'Select your date of birth',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _confirmAndVerify() async {
    if (_selectedDate == null) return;

    final formatted = _formatDate(_selectedDate!);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your date of birth'),
        content: Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Your date of birth: '),
              TextSpan(
                text: formatted,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text: '.\n\nThis cannot be changed later.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Go Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).verifyAge(_selectedDate!);
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

  @override
  Widget build(BuildContext context) {
    final formatted =
        _selectedDate != null ? _formatDate(_selectedDate!) : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SwappTokens.spacingXl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "When's your birthday?",
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SwappTokens.spacingMd),
                Text(
                  'This helps us set up your account',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SwappTokens.spacingXxl),

                // Date picker field
                GestureDetector(
                  onTap: _isLoading ? null : _pickDate,
                  child: AbsorbPointer(
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Date of birth',
                        hintText: 'Select date',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        suffixIcon:
                            const Icon(Icons.calendar_today_outlined),
                      ),
                      controller:
                          TextEditingController(text: formatted ?? ''),
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: SwappTokens.spacingXxl),

                // Continue button
                SwappButton(
                  label: 'Continue',
                  onPressed:
                      _selectedDate != null ? _confirmAndVerify : null,
                  isLoading: _isLoading,
                  isExpanded: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
