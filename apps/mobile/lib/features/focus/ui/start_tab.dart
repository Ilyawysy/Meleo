import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/adaptive_plan_provider.dart';
import '../providers/focus_rooms_provider.dart';
import '../providers/today_focus_progress_provider.dart';
import 'start/adaptive_plan_widget.dart';
import 'start/focus_days_row.dart';
import 'start/focus_start_header.dart';
import 'start/rooms_section.dart';
import 'start/today_progress_ring.dart';

class StartTab extends ConsumerWidget {
  final VoidCallback onRoomSelected;

  const StartTab({super.key, required this.onRoomSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(focusRoomsProvider);
          ref.invalidate(adaptivePlanProvider);
          ref.invalidate(todayFocusProgressProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(
              child: FocusStartHeader(),
            ),
            const SliverToBoxAdapter(
              child: FocusDaysRow(),
            ),
            const SliverToBoxAdapter(
              child: TodayProgressRing(),
            ),
            SliverToBoxAdapter(
              child: AdaptivePlanWidget(onRoomSelected: onRoomSelected),
            ),
            RoomsSection(onRoomSelected: onRoomSelected),
          ],
        ),
      ),
    );
  }
}
