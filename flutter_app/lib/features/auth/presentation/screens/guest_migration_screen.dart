import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/features/auth/data/providers/guest_migration_providers.dart';
import 'package:flutter_app/features/auth/data/services/auth_service.dart';
import 'package:flutter_app/features/auth/data/providers/auth_providers.dart';
import 'package:flutter_app/features/stickers/data/providers/guest_inventory_providers.dart';
import 'package:flutter_app/shared/shared.dart';

enum _MigrationState { prompt, migrating, success, error }

class GuestMigrationScreen extends ConsumerStatefulWidget {
  const GuestMigrationScreen({super.key});

  @override
  ConsumerState<GuestMigrationScreen> createState() =>
      _GuestMigrationScreenState();
}

class _GuestMigrationScreenState extends ConsumerState<GuestMigrationScreen> {
  _MigrationState _state = _MigrationState.prompt;
  String? _errorMessage;
  int _itemsWritten = 0;
  int _stickerCount = 0;

  Future<void> _startMigration() async {
    setState(() => _state = _MigrationState.migrating);

    try {
      final inventory = ref.read(guestInventoryProvider).value ?? {};
      if (inventory.isEmpty) {
        _markComplete();
        return;
      }

      final storageService = ref.read(guestStorageServiceProvider);
      final deviceUuid = await storageService.getOrCreateDeviceUuid();

      final items = inventory
          .map((id) => {
                'sticker_id': id,
                'status': 'OWNED',
                'quantity': 1,
              })
          .toList();

      final result = await ref.read(authServiceProvider).migrateGuestInventory(
            deviceUuid: deviceUuid,
            items: items,
          );

      // Clear local inventory after successful migration
      await storageService.clearInventory();

      if (mounted) {
        setState(() {
          _itemsWritten = result.itemsWritten;
          _state = _MigrationState.success;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _state = _MigrationState.error;
        });
      }
    }
  }

  void _markComplete() {
    ref.read(guestMigrationCompleteProvider.notifier).complete();
  }

  void _skip() {
    _markComplete();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inventory = ref.watch(guestInventoryProvider).value ?? {};
    _stickerCount = inventory.length;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(SwappTokens.spacingXl),
            child: switch (_state) {
              _MigrationState.prompt => _buildPrompt(colorScheme, textTheme),
              _MigrationState.migrating =>
                _buildMigrating(colorScheme, textTheme),
              _MigrationState.success => _buildSuccess(colorScheme, textTheme),
              _MigrationState.error => _buildError(colorScheme, textTheme),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPrompt(ColorScheme colorScheme, TextTheme textTheme) {
    final count = _stickerCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.sync_outlined,
          size: 64,
          color: colorScheme.primary,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Transfer Your Collection',
          style: textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          'You have $count sticker${count == 1 ? '' : 's'} saved on this '
          'device. Transfer them to your new account so you can access '
          'them anywhere.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        SwappButton(
          label: 'Transfer Stickers',
          onPressed: _startMigration,
          isExpanded: true,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        SwappButton(
          label: 'Skip',
          variant: SwappButtonVariant.outlined,
          onPressed: _skip,
          isExpanded: true,
        ),
      ],
    );
  }

  Widget _buildMigrating(ColorScheme colorScheme, TextTheme textTheme) {
    final count = _stickerCount;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: 64,
          color: colorScheme.primary,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Transferring Stickers',
          style: textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          'Moving $count sticker${count == 1 ? '' : 's'} to your account...',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: SwappTokens.spacingLg),
          child: CircularProgressIndicator(),
        ),
      ],
    );
  }

  Widget _buildSuccess(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: colorScheme.tertiary,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Transfer Complete',
          style: textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          '$_itemsWritten sticker${_itemsWritten == 1 ? '' : 's'} '
          'transferred to your account.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        SwappButton(
          label: 'Continue',
          onPressed: _markComplete,
          isExpanded: true,
        ),
      ],
    );
  }

  Widget _buildError(ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline,
          size: 64,
          color: colorScheme.error,
        ),
        const SizedBox(height: SwappTokens.spacingXl),
        Text(
          'Transfer Failed',
          style: textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        Text(
          _errorMessage ?? 'Something went wrong. Your stickers are still '
              'saved on this device.',
          style: textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: SwappTokens.spacingXxl),
        SwappButton(
          label: 'Retry',
          onPressed: _startMigration,
          isExpanded: true,
        ),
        const SizedBox(height: SwappTokens.spacingMd),
        SwappButton(
          label: 'Skip for Now',
          variant: SwappButtonVariant.outlined,
          onPressed: _skip,
          isExpanded: true,
        ),
      ],
    );
  }
}
