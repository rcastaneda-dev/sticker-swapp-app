import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/shared/shared.dart';
import '../../data/models/sticker.dart';
import '../../data/providers/sticker_providers.dart';
import '../../data/providers/effective_inventory_providers.dart';
import '../../data/providers/user_inventory_providers.dart';

class StickerCatalogScreen extends ConsumerWidget {
  const StickerCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stickersAsync = ref.watch(stickerListProvider);
    final filter = ref.watch(stickerFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sticker Catalog'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Collection progress',
            onPressed: () => context.push('/catalog/progress'),
          ),
          if (filter.team != null || filter.type != null)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear filters',
              onPressed: () =>
                  ref.read(stickerFilterProvider.notifier).clearAll(),
            ),
        ],
      ),
      body: Column(
        children: [
          _FilterBar(filter: filter),
          const _CollectionProgress(),
          Expanded(
            child: stickersAsync.when(
              data: (stickers) => stickers.isEmpty
                  ? const _EmptyState()
                  : _StickerGrid(stickers: stickers),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(stickerListProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Bar ──────────────────────────────────────────────────────

class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter});
  final StickerFilter filter;

  static const _types = ['player', 'stadium', 'legend'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
        vertical: SwappTokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type filter chips
          SizedBox(
            height: SwappTokens.buttonHeightSm,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _TypeChip(
                  label: 'All',
                  selected: filter.type == null,
                  onSelected: () => ref
                      .read(stickerFilterProvider.notifier)
                      .setType(null),
                ),
                const SizedBox(width: SwappTokens.spacingSm),
                for (final type in _types) ...[
                  _TypeChip(
                    label: _typeLabel(type),
                    selected: filter.type == type,
                    onSelected: () => ref
                        .read(stickerFilterProvider.notifier)
                        .setType(type),
                  ),
                  const SizedBox(width: SwappTokens.spacingSm),
                ],
              ],
            ),
          ),
          const SizedBox(height: SwappTokens.spacingSm),

          // Team filter button
          _TeamFilterButton(
            currentTeam: filter.team,
            textColor: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  static String _typeLabel(String type) {
    return switch (type) {
      'player' => 'Players',
      'stadium' => 'Stadiums',
      'legend' => 'Legends',
      _ => type,
    };
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
    );
  }
}

class _TeamFilterButton extends ConsumerWidget {
  const _TeamFilterButton({
    required this.currentTeam,
    required this.textColor,
  });

  final String? currentTeam;
  final Color textColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(teamListProvider);

    return InkWell(
      onTap: () {
        final teams = teamsAsync.value;
        if (teams != null) {
          _showTeamPicker(context, ref, teams);
        }
      },
      borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SwappTokens.spacingMd,
          vertical: SwappTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 18, color: textColor),
            const SizedBox(width: SwappTokens.spacingSm),
            Text(
              currentTeam ?? 'All Teams',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: textColor),
            ),
            const SizedBox(width: SwappTokens.spacingXs),
            Icon(Icons.arrow_drop_down, size: 20, color: textColor),
          ],
        ),
      ),
    );
  }

  void _showTeamPicker(
    BuildContext context,
    WidgetRef ref,
    List<String> teams,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => _TeamPickerSheet(
          teams: teams,
          currentTeam: currentTeam,
          scrollController: scrollController,
          onSelected: (team) {
            ref.read(stickerFilterProvider.notifier).setTeam(team);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}

class _TeamPickerSheet extends StatefulWidget {
  const _TeamPickerSheet({
    required this.teams,
    required this.currentTeam,
    required this.scrollController,
    required this.onSelected,
  });

  final List<String> teams;
  final String? currentTeam;
  final ScrollController scrollController;
  final void Function(String?) onSelected;

  @override
  State<_TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends State<_TeamPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _search.isEmpty
        ? widget.teams
        : widget.teams
            .where((t) => t.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: SwappTokens.spacingMd),
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(SwappTokens.radiusFull),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(SwappTokens.spacingLg),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search teams...',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: widget.scrollController,
            itemCount: filtered.length + 1, // +1 for "All Teams"
            itemBuilder: (context, index) {
              if (index == 0) {
                final isSelected = widget.currentTeam == null;
                return ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(
                    'All Teams',
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onTap: () => widget.onSelected(null),
                );
              }
              final team = filtered[index - 1];
              final isSelected = team == widget.currentTeam;
              final (primary, _) = TeamColors.forTeam(team);
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: primary,
                ),
                title: Text(
                  team,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                onTap: () => widget.onSelected(team),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Collection Progress ─────────────────────────────────────────────

class _CollectionProgress extends ConsumerWidget {
  const _CollectionProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(effectiveInventoryProvider);
    final ownedCount = inventoryAsync.value?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SwappTokens.spacingLg,
        vertical: SwappTokens.spacingXs,
      ),
      child: SwappProgressBar(
        current: ownedCount,
        total: 980,
        label: 'Collection',
        showPercentage: true,
      ),
    );
  }
}

// ── Sticker Grid ────────────────────────────────────────────────────

class _StickerGrid extends StatelessWidget {
  const _StickerGrid({required this.stickers});
  final List<Sticker> stickers;

  @override
  Widget build(BuildContext context) {
    // Compute column count based on available width.
    // Target: ~100px per tile including spacing.
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            (constraints.maxWidth / 100).floor().clamp(3, 6);

        return CustomScrollView(
          slivers: [
            // Result count
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SwappTokens.spacingLg,
                  vertical: SwappTokens.spacingXs,
                ),
                child: Text(
                  '${stickers.length} stickers',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ),

            // Grid
            SliverPadding(
              padding: const EdgeInsets.all(SwappTokens.spacingSm),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => RepaintBoundary(
                    child: _StickerGridTile(sticker: stickers[index]),
                  ),
                  childCount: stickers.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: false, // We add our own above
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: SwappTokens.spacingSm,
                  crossAxisSpacing: SwappTokens.spacingSm,
                  childAspectRatio: 0.75,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickerGridTile extends ConsumerWidget {
  const _StickerGridTile({required this.sticker});
  final Sticker sticker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final inventoryAsync = ref.watch(effectiveInventoryProvider);
    final isOwned = inventoryAsync.value?.contains(sticker.id) ?? false;
    final reservedAsync = ref.watch(reservedStickersProvider);
    final isReserved = reservedAsync.value?.contains(sticker.id) ?? false;

    return GestureDetector(
      onTap: () => toggleEffectiveSticker(ref, sticker.id),
      child: SwappCard(
        variant: SwappCardVariant.outlined,
        padding: const EdgeInsets.all(SwappTokens.spacingXs),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Opacity(
                    opacity: isOwned ? 1.0 : 0.4,
                    child: SwappStickerImage(
                      stickerNumber: sticker.stickerNumber,
                      imageUrl: sticker.imageUrl,
                      team: sticker.team,
                      type: sticker.type,
                      size: StickerImageSize.thumbnail,
                    ),
                  ),
                ),
                const SizedBox(height: SwappTokens.spacingXs),
                Text(
                  '#${sticker.stickerNumber}',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  sticker.team ?? sticker.title,
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            if (isReserved)
              Positioned(
                top: 2,
                right: 2,
                child: Tooltip(
                  message: 'Reserved for an active trade',
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.secondary,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.lock,
                      size: 12,
                      color: colorScheme.onSecondary,
                    ),
                  ),
                ),
              )
            else if (isOwned)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.check,
                    size: 12,
                    color: colorScheme.onTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Empty / Error States ────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: SwappTokens.spacingLg),
          Text(
            'No stickers match your filters',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: SwappTokens.spacingLg),
          Text(
            'Failed to load stickers',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: SwappTokens.spacingMd),
          SwappButton(
            label: 'Retry',
            onPressed: onRetry,
            variant: SwappButtonVariant.outlined,
            size: SwappButtonSize.small,
          ),
        ],
      ),
    );
  }
}
