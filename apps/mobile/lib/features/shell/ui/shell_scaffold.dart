import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/analytics_service.dart';
import '../../../core/sync/sync_bridge_provider.dart';
import '../../focus/ui/focus_tab.dart';
import '../../focus/ui/start_tab.dart';
import '../../focus/ui/profile_tab.dart';
import '../../focus/providers/focus_provider.dart';
import '../../statistics/ui/statistics_tab.dart';
import 'custom_bottom_nav.dart';

class ShellScaffold extends ConsumerStatefulWidget {
  const ShellScaffold({super.key});
  @override
  ConsumerState<ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<ShellScaffold> {
  // Tabs: 0=START, 1=FOCUS, 2=STATS, 3=PROFILE
  int _index = 0;
  final _focusTabKey = GlobalKey<FocusTabState>();
  bool _focusSessionActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AnalyticsService().trackScreen('Start');
    });
  }

  void _onNavTap(int navIdx) {
    setState(() => _index = navIdx);

    switch (navIdx) {
      case 0:
        AnalyticsService().trackScreen('Start');
        break;
      case 1:
        AnalyticsService().trackScreen('Focus');
        break;
      case 2:
        AnalyticsService().trackScreen('Statistics');
        break;
      case 3:
        AnalyticsService().trackScreen('Profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(syncBridgeProvider);

    final pages = [
      // 0 — START
      StartTab(
        onRoomSelected: () {
          setState(() => _index = 1);
          AnalyticsService().trackScreen('Focus');
        },
      ),
      // 1 — FOCUS
      FocusTab(
        key: _focusTabKey,
        initialData: ref.watch(focusProvider),
        onRefreshFocus: () {
          ref.read(focusProvider.notifier).refresh();
        },
        onSessionViewChanged: (viewing) {
          setState(() => _focusSessionActive = viewing);
        },
      ),
      // 2 — STATS
      const StatisticsTab(),
      // 3 — PROFILE
      const ProfileTab(),
    ];

    final hideNav = _index == 1 && _focusSessionActive;

    return Scaffold(
      appBar: null,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: hideNav
          ? null
          : CustomBottomNav(
              selectedIndex: _index,
              onTap: _onNavTap,
            ),
    );
  }
}
