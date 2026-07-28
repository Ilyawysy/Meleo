import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design/app_colors.dart';
import '../../chat/ui/chat_screen.dart';
import '../../profile/ui/settings_screen.dart';
import '../../subscription/providers/subscription_provider.dart';
import '../../subscription/ui/pro_upgrade_sheet.dart';
import 'pages/stats_over_page.dart';
import 'pages/stats_focus_page.dart';
import 'pages/stats_rooms_page.dart';
import 'pages/stats_comp_page.dart';

class StatisticsTab extends ConsumerStatefulWidget {
  const StatisticsTab({super.key});

  @override
  ConsumerState<StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends ConsumerState<StatisticsTab> {
  int _selectedIndex = 0;
  final Set<int> _visited = {0};

  static const _tabLabels = ['Over', 'Focus', 'Rooms', 'Comp'];

  void _onTabTap(int index) {
    if (index == 0) {
      setState(() => _selectedIndex = index);
      return;
    }
    final isPro = ref.read(subscriptionProvider).isPro;
    if (!isPro) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const ProUpgradeSheet(),
      );
      return;
    }
    setState(() {
      _selectedIndex = index;
      _visited.add(index);
    });
  }

  Widget _pageFor(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    switch (i) {
      case 0:
        return const StatsOverPage();
      case 1:
        return const StatsFocusPage();
      case 2:
        return const StatsRoomsPage();
      case 3:
        return const StatsCompPage();
      default:
        return const SizedBox.shrink();
    }
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _headerDateLabel() {
    final now = DateTime.now();
    final wd = _weekdays[now.weekday - 1];
    final day = now.day.toString().padLeft(2, '0');
    final mo = _months[now.month - 1];
    return '$wd, $day $mo';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          _buildTabsRow(),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                _pageFor(0),
                _pageFor(1),
                _pageFor(2),
                _pageFor(3),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: AI chat button (matches help-button style on focus room)
          _AskAiButton(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ChatScreen(),
                ),
              );
            },
          ),
          // Center: date + title
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _headerDateLabel(),
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textLight,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'FOCUS DAY',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF18181B),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          // Right: settings button
          _CircleButton(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
            child: const Icon(Icons.settings, size: 18, color: Color(0xFF18181B)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: List.generate(_tabLabels.length, (i) {
            final isActive = _selectedIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => _onTabTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isActive ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0x0D000000),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabLabels[i],
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF18181B)
                          : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _CircleButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// Mirrors `_HelpButton` style from focus_room.dart: pale-blue fill,
/// dashed primary-blue border, bold blue text label.
class _AskAiButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AskAiButton({required this.onTap});

  static const _fill = Color(0xFFDBEAFE);
  static const _stroke = Color(0xFF2563EB);
  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: _stroke,
          radius: _radius,
          strokeWidth: 1.5,
          dashLength: 5,
          gapLength: 4,
        ),
        child: Container(
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(_radius),
          ),
          alignment: Alignment.center,
          child: const Text(
            'ai',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _stroke,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}
