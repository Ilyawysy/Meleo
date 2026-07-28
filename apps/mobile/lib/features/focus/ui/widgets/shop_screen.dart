import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../models/focus_models.dart';

class ShopScreen extends StatefulWidget {
  final ValueNotifier<double> coinsNotifier;
  final ValueNotifier<List<ShopItem>> itemsNotifier;
  final ValueNotifier<ActiveItems> activeItemsNotifier;
  final ValueChanged<ShopItem> onPurchase;
  final ValueChanged<ShopItem> onActivate;
  final int userLevel;

  const ShopScreen({
    super.key,
    required this.coinsNotifier,
    required this.itemsNotifier,
    required this.activeItemsNotifier,
    required this.onPurchase,
    required this.onActivate,
    required this.userLevel,
  });

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  int _tabIndex = 0;
  static const _tabs = ['Mascot', 'Themes', 'Boosts'];

  List<ShopItem> _filtered(List<ShopItem> items) {
    if (_tabIndex == 0) {
      return items.where((i) =>
        i.category == ShopItemCategory.skin ||
        i.category == ShopItemCategory.aura ||
        i.category == ShopItemCategory.environment
      ).toList();
    }
    if (_tabIndex == 1) {
      return items.where((i) => i.category == ShopItemCategory.theme).toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabs(),
            Expanded(
              child: ValueListenableBuilder<List<ShopItem>>(
                valueListenable: widget.itemsNotifier,
                builder: (context, items, _) {
                  final filtered = _filtered(items);
                  if (_tabIndex == 0) {
                    return _buildMascotTab(filtered);
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        'No items available',
                        style: AppTypography.body15(color: AppColors.textLight),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return ValueListenableBuilder<double>(
                        valueListenable: widget.coinsNotifier,
                        builder: (context, coins, _) =>
                            _buildItemCard(item, coins),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.greyBgDarker,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, size: 18, color: AppColors.textDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Shop', style: AppTypography.heading22()),
          ),
          ValueListenableBuilder<double>(
            valueListenable: widget.coinsNotifier,
            builder: (context, coins, _) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Text(
                    coins.toStringAsFixed(0),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(_tabs.length, (i) {
          final selected = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tabIndex = i),
              child: Container(
                padding: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: selected ? AppColors.primaryBlue : AppColors.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  _tabs[i],
                  style: AppTypography.body15(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? AppColors.primaryBlue : AppColors.textMedium,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMascotTab(List<ShopItem> items) {
    return ValueListenableBuilder<ActiveItems>(
      valueListenable: widget.activeItemsNotifier,
      builder: (context, activeItems, _) {
        final skins = items.where((i) => i.category == ShopItemCategory.skin).toList();
        final auras = items.where((i) => i.category == ShopItemCategory.aura).toList();
        final envs = items.where((i) => i.category == ShopItemCategory.environment).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildActiveLoadout(activeItems, items),
              const SizedBox(height: 24),
              if (skins.isNotEmpty) ...[
                Text('Skins', style: AppTypography.body15(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildItemGrid(skins, activeItems),
                const SizedBox(height: 24),
              ],
              if (auras.isNotEmpty) ...[
                Text('Auras', style: AppTypography.body15(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildItemGrid(auras, activeItems),
                const SizedBox(height: 24),
              ],
              if (envs.isNotEmpty) ...[
                Text('Environments', style: AppTypography.body15(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                _buildItemGrid(envs, activeItems),
              ],
              if (skins.isEmpty && auras.isEmpty && envs.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text(
                      'No items available',
                      style: AppTypography.body15(color: AppColors.textLight),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActiveLoadout(ActiveItems activeItems, List<ShopItem> allItems) {
    String activeName(String? itemId) {
      if (itemId == null) return 'None';
      final item = allItems.where((i) => i.id == itemId).firstOrNull;
      return item?.name ?? 'None';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Active Loadout', style: AppTypography.body15(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _loadoutRow(Icons.pets, 'Skin', activeName(activeItems.skin)),
          const SizedBox(height: 8),
          _loadoutRow(Icons.auto_awesome, 'Aura', activeName(activeItems.aura)),
          const SizedBox(height: 8),
          _loadoutRow(Icons.landscape, 'Environment', activeName(activeItems.environment)),
        ],
      ),
    );
  }

  Widget _loadoutRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMedium),
        const SizedBox(width: 8),
        Text('$label: ', style: AppTypography.body14(color: AppColors.textMedium)),
        Text(value, style: AppTypography.body14(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildItemGrid(List<ShopItem> items, ActiveItems activeItems) {
    return ValueListenableBuilder<double>(
      valueListenable: widget.coinsNotifier,
      builder: (context, coins, _) {
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isActive = _isItemActive(item, activeItems);
            return _buildItemCard(item, coins, isActive: isActive);
          },
        );
      },
    );
  }

  bool _isItemActive(ShopItem item, ActiveItems activeItems) {
    switch (item.category) {
      case ShopItemCategory.aura:
        return activeItems.aura == item.id;
      case ShopItemCategory.skin:
        return activeItems.skin == item.id;
      case ShopItemCategory.environment:
        return activeItems.environment == item.id;
      default:
        return false;
    }
  }

  Widget _buildItemCard(ShopItem item, double coins, {bool isActive = false}) {
    final canBuy = !item.owned && coins >= item.price;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Icon(
                _categoryIcon(item.category),
                size: 48,
                color: AppColors.textLight,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.name,
            style: AppTypography.body14(fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          _buildItemButton(item, canBuy, coins, isActive: isActive),
        ],
      ),
    );
  }

  Widget _buildItemButton(ShopItem item, bool canBuy, double coins, {bool isActive = false}) {
    // Check level requirement for unowned items
    if (item.requiredLevel > widget.userLevel && !item.owned) {
      return Container(
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.greyBgDarker,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          'Lvl ${item.requiredLevel}',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textLight,
          ),
        ),
      );
    }

    if (item.owned || item.price == 0) {
      if (isActive) {
        return Container(
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFDCFCE7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF22C55E)),
          ),
          alignment: Alignment.center,
          child: Text(
            'Active',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF16A34A),
            ),
          ),
        );
      }

      const activatableCategories = {
        ShopItemCategory.aura,
        ShopItemCategory.skin,
        ShopItemCategory.environment,
      };
      if (activatableCategories.contains(item.category)) {
        return GestureDetector(
          onTap: () => widget.onActivate(item),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primaryBlue),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              'Use',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        );
      }

      return Container(
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          'Use',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textMedium,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: canBuy ? () => widget.onPurchase(item) : null,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          gradient: canBuy
              ? const LinearGradient(
                  colors: [AppColors.gradientStart, AppColors.gradientEnd],
                )
              : null,
          color: canBuy ? null : AppColors.greyBgDarker,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.monetization_on, size: 14, color: Color(0xFFFFD700)),
            const SizedBox(width: 4),
            Text(
              item.price.toStringAsFixed(0),
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: canBuy ? AppColors.white : AppColors.textLight,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(ShopItemCategory category) {
    switch (category) {
      case ShopItemCategory.hat:
        return Icons.face_retouching_natural;
      case ShopItemCategory.top:
        return Icons.checkroom;
      case ShopItemCategory.bottom:
        return Icons.accessibility_new;
      case ShopItemCategory.shoes:
        return Icons.directions_walk;
      case ShopItemCategory.accessory:
        return Icons.star_outline;
      case ShopItemCategory.theme:
        return Icons.palette_outlined;
      case ShopItemCategory.aura:
        return Icons.auto_awesome;
      case ShopItemCategory.skin:
        return Icons.pets;
      case ShopItemCategory.environment:
        return Icons.landscape;
    }
  }
}
