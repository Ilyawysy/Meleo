import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../logic/growth_calculator.dart';
import '../../models/adaptive_plan.dart';
import '../../models/focus_room.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/adaptive_plan_provider.dart';
import '../../providers/focus_rooms_provider.dart';
import '../../providers/plan_widget_mode_provider.dart';
import '../overlays/adaptive_plan_sheet.dart';
import '../overlays/growth_active_sheet.dart';

class AdaptivePlanWidget extends ConsumerWidget {
  final VoidCallback onRoomSelected;

  const AdaptivePlanWidget({super.key, required this.onRoomSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(planWidgetModeProvider);
    final planAsync = ref.watch(adaptivePlanProvider);
    final roomsAsync = ref.watch(focusRoomsProvider);

    final plan = planAsync.valueOrNull;
    final rooms = roomsAsync.valueOrNull ?? [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: GestureDetector(
        onTap: () => _handleTap(context, ref, mode, rooms),
        child: planAsync.isLoading && plan == null
            ? _LoadingStubCard()
            : switch (mode) {
                PlanWidgetMode.empty => _EmptyCard(),
                PlanWidgetMode.plan => _PlanCard(plan: plan),
                PlanWidgetMode.growth => _GrowthCard(plan: plan),
                PlanWidgetMode.sprint => _SprintCard(
                    rooms: rooms,
                  ),
              },
      ),
    );
  }

  void _handleTap(
    BuildContext context,
    WidgetRef ref,
    PlanWidgetMode mode,
    List<FocusRoom> rooms,
  ) {
    if (mode == PlanWidgetMode.sprint) {
      final sprintRoom = rooms
          .cast<FocusRoom?>()
          .firstWhere(
            (r) => r!.type == FocusRoomType.sprint && !r.archived,
            orElse: () => null,
          );
      if (sprintRoom == null) return;
      ref.read(activeRoomIdProvider.notifier).set(sprintRoom.id);
      onRoomSelected();
      return;
    }

    if (mode == PlanWidgetMode.growth) {
      showGrowthActiveSheet(context);
      return;
    }

    showAdaptivePlanDialog(context);
  }
}

// ---------------------------------------------------------------------------
// Empty card
// ---------------------------------------------------------------------------

class _EmptyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.add_chart_outlined,
              color: AppColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set up your focus plan',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to configure growth, sprint or custom plan',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSlate,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: AppColors.textLight, size: 20),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loading stub card — same dimensions as _EmptyCard, shown while plan loads
// ---------------------------------------------------------------------------

class _LoadingStubCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 11,
                  width: 180,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plan card — shows 7-bar mini chart
// ---------------------------------------------------------------------------

class _PlanCard extends StatelessWidget {
  final AdaptivePlan? plan;
  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final hours = plan?.hoursPerDay ?? List.filled(7, 0);
    final total = hours.fold<int>(0, (s, h) => s + h);
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final maxH = hours.isEmpty ? 1 : hours.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'This week',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const Spacer(),
              Text(
                '${total}h planned',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) {
                final h = hours.length > i ? hours[i] : 0;
                final barH = maxH > 0 ? (h / maxH * 42).clamp(4.0, 42.0) : 4.0;
                final isToday = i == DateTime.now().weekday - 1;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 22,
                      height: h > 0 ? barH : 4,
                      decoration: BoxDecoration(
                        color: h > 0
                            ? (isToday
                                ? AppColors.primaryBlue
                                : AppColors.primaryBlue
                                    .withValues(alpha: 0.35))
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dayLabels[i],
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: isToday
                            ? AppColors.primaryBlue
                            : AppColors.textLight,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Growth card
// ---------------------------------------------------------------------------

class _GrowthCard extends StatelessWidget {
  final AdaptivePlan? plan;
  const _GrowthCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    if (plan == null ||
        plan!.growthTargetHours == null ||
        plan!.growthStartedAt == null ||
        plan!.growthSpeed == null) {
      return _EmptyCard();
    }

    final base = basePlanTotalHours(plan!.hoursPerDay);
    final target = plan!.growthTargetHours!;
    final startedAt = plan!.growthStartedAt!;
    final speed = plan!.growthSpeed!;
    final now = DateTime.now();

    final current = currentWeeklyTargetHours(
      basePlanTotal: base,
      targetTotal: target,
      startedAt: startedAt,
      speed: speed,
      now: now,
    );
    final totalWeeks = weeksToTarget(speed);
    final elapsed = weeksSinceStart(startedAt, now);
    final progress = target > base
        ? ((current - base) / (target - base)).clamp(0.0, 1.0)
        : 0.0;

    final speedLabel = switch (speed) {
      GrowthSpeed.steady => 'Steady',
      GrowthSpeed.faster => 'Faster',
      GrowthSpeed.push => 'Push',
    };

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFBBF7D0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up,
                  color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 6),
              Text(
                'Growth',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF16A34A),
                ),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  color: Color(0xFF16A34A), size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${current}h',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '${target}h',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFD1FAE5),
              valueColor: const AlwaysStoppedAnimation(Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Week ${elapsed + 1} of $totalWeeks · $speedLabel',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textSlate,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sprint card
// ---------------------------------------------------------------------------

class _SprintCard extends StatelessWidget {
  final List<FocusRoom> rooms;
  const _SprintCard({required this.rooms});

  @override
  Widget build(BuildContext context) {
    final sprintRoom = rooms
        .cast<FocusRoom?>()
        .firstWhere(
          (r) => r!.type == FocusRoomType.sprint && !r.archived,
          orElse: () => null,
        );
    if (sprintRoom == null) return const SizedBox.shrink();

    final deadline = sprintRoom.sprintDeadline;
    final daysLeft = deadline != null
        ? deadline.difference(DateTime.now()).inDays.clamp(0, 9999)
        : 0;
    final total = sprintRoom.sprintTotalHours ?? 0;
    final doneSec = sprintRoom.totalFocusSec;
    final doneH = doneSec ~/ 3600;
    final progress =
        total > 0 ? (doneH / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Sprint: ${sprintRoom.sprintGoal ?? sprintRoom.title}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFD97706),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$daysLeft days left',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${doneH}h',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Text(
                '${total}h total',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSlate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFFEF3C7),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFD97706)),
            ),
          ),
        ],
      ),
    );
  }
}
