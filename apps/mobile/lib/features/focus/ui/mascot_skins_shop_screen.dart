import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../models/mascot_skin.dart';
import '../providers/mascot_skins_provider.dart';
import 'widgets/mascot.dart';

class MascotSkinsShopScreen extends ConsumerWidget {
  /// Live display-coins balance. Decremented optimistically on purchase.
  /// Owned by the caller (focus_tab) which persists changes to local DB.
  final ValueNotifier<double> coinsNotifier;

  const MascotSkinsShopScreen({super.key, required this.coinsNotifier});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mascotSkinsProvider);
    final catalog = state.catalog;

    return Scaffold(
      backgroundColor: AppColors.greyBg,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        title: Text('Mascot Skins', style: AppTypography.heading18()),
        centerTitle: false,
        leading: const BackButton(color: AppColors.textDark),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: coinsNotifier,
                builder: (_, coins, __) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.greyBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.monetization_on,
                          size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        coins.toStringAsFixed(0),
                        style: AppTypography.body14(
                            color: const Color(0xFFF59E0B)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: catalog == null
          ? Center(
              child: state.error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Failed to load shop:\n${state.error}',
                        style: AppTypography.body14(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : _buildBody(context, ref, catalog),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    MascotSkinsCatalog catalog,
  ) {
    final groups = <MascotSkinTier, List<MascotSkin>>{
      for (final tier in MascotSkinTier.values)
        tier: catalog.skins.where((s) => s.tier == tier).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (var i = 0; i < MascotSkinTier.values.length; i++) ...[
          _GroupGrid(skins: groups[MascotSkinTier.values[i]] ?? const []),
          if (i < MascotSkinTier.values.length - 1)
            const SizedBox(height: 32),
        ],
      ],
    );
  }
}

class _GroupGrid extends StatelessWidget {
  final List<MascotSkin> skins;
  const _GroupGrid({required this.skins});

  @override
  Widget build(BuildContext context) {
    if (skins.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, c) {
        const spacing = 12.0;
        final cardW = (c.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final s in skins)
              SizedBox(
                width: cardW,
                child: _SkinCard(skin: s),
              ),
          ],
        );
      },
    );
  }
}

class _SkinCard extends ConsumerWidget {
  final MascotSkin skin;
  const _SkinCard({required this.skin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(mascotSkinsProvider.notifier);
    final shop =
        context.findAncestorWidgetOfExactType<MascotSkinsShopScreen>()!;
    final coinsNotifier = shop.coinsNotifier;

    Future<void> handleBuy() async {
      if (coinsNotifier.value < skin.priceCoins) {
        // No purchase attempt — UX is the "Need N coins" disabled state.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Не хватает ${skin.priceCoins - coinsNotifier.value.floor()} монет'),
          ),
        );
        return;
      }
      // Optimistic: decrement balance, mark owned.
      coinsNotifier.value = coinsNotifier.value - skin.priceCoins;
      try {
        await notifier.buy(skin.id);
      } catch (e) {
        // Rollback balance — owned was already rolled back inside notifier.buy.
        coinsNotifier.value = coinsNotifier.value + skin.priceCoins;
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка покупки')),
        );
      }
    }

    Future<void> handleActivate() async {
      try {
        await notifier.setActive(skin.id);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка активации')),
        );
      }
    }

    Future<void> handleDeactivate() async {
      try {
        await notifier.setActive(null);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка')),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: skin.active ? AppColors.primaryBlue : AppColors.border,
          width: skin.active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
              child: ColoredBox(
                color: AppColors.greyBg,
                child: Mascot(
                  mode: MascotMode.dinner,
                  size: 200,
                  skinOverride: skin,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: ValueListenableBuilder<double>(
              valueListenable: coinsNotifier,
              builder: (_, coins, __) => _bottomRow(
                context: context,
                coins: coins,
                onBuy: handleBuy,
                onActivate: handleActivate,
                onDeactivate: handleDeactivate,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomRow({
    required BuildContext context,
    required double coins,
    required VoidCallback onBuy,
    required VoidCallback onActivate,
    required VoidCallback onDeactivate,
  }) {
    if (skin.active) {
      return SizedBox(
        height: 36,
        child: OutlinedButton(
          onPressed: onDeactivate,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Active',
            style: AppTypography.body13(color: AppColors.primaryBlue),
          ),
        ),
      );
    }
    if (skin.owned) {
      return SizedBox(
        height: 36,
        child: FilledButton(
          onPressed: onActivate,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Activate'),
        ),
      );
    }
    final canAfford = coins >= skin.priceCoins;
    return SizedBox(
      height: 36,
      child: FilledButton(
        onPressed: canAfford ? onBuy : null,
        style: FilledButton.styleFrom(
          backgroundColor: canAfford
              ? AppColors.primaryBlue
              : AppColors.greyBg,
          disabledBackgroundColor: AppColors.greyBg,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.monetization_on,
              size: 16,
              color: canAfford ? Colors.white : AppColors.textLight,
            ),
            const SizedBox(width: 4),
            Text(
              skin.priceCoins.toString(),
              style: AppTypography.body14(
                color: canAfford ? Colors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
