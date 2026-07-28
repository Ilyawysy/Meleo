import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../logic/growth_calculator.dart';
import '../../models/adaptive_plan.dart';
import '../../providers/adaptive_plan_provider.dart';
import 'shared/hour_picker.dart';

class GrowthSetupSheet extends ConsumerStatefulWidget {
  const GrowthSetupSheet({super.key});

  @override
  ConsumerState<GrowthSetupSheet> createState() => _GrowthSetupSheetState();
}

class _GrowthSetupSheetState extends ConsumerState<GrowthSetupSheet> {
  late int _targetHours;
  GrowthSpeed _speed = GrowthSpeed.steady;
  bool _saving = false;

  int get _base {
    final plan = ref.read(adaptivePlanProvider).valueOrNull;
    return basePlanTotalHours(plan?.hoursPerDay);
  }

  @override
  void initState() {
    super.initState();
    final plan = ref.read(adaptivePlanProvider).valueOrNull;
    final base = basePlanTotalHours(plan?.hoursPerDay);
    _targetHours = (plan?.growthTargetHours ?? base + 5).clamp(base + 1, 60);
    _speed = plan?.growthSpeed ?? GrowthSpeed.steady;
  }

  Future<void> _pickTarget() async {
    final base = _base;
    final picked = await showHourPicker(
      context,
      initial: _targetHours,
      min: base + 1,
      max: 60,
    );
    if (picked != null && mounted) {
      setState(() => _targetHours = picked);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(adaptivePlanProvider.notifier)
          .startGrowth(_targetHours, _speed);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    final hasBase = base > 0;
    final completion = estimatedCompletionDate(
      startedAt: DateTime.now(),
      speed: _speed,
    );
    final totalWeeks = weeksToTarget(_speed);
    final progressFraction =
        base > 0 ? ((base) / _targetHours).clamp(0.0, 1.0) : 0.0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: _buildContent(
          base: base,
          hasBase: hasBase,
          completion: completion,
          totalWeeks: totalWeeks,
          progressFraction: progressFraction,
        ),
      ),
    );
  }

  Widget _buildContent({
    required int base,
    required bool hasBase,
    required DateTime completion,
    required int totalWeeks,
    required double progressFraction,
  }) {
    final speedLabel = switch (_speed) {
      GrowthSpeed.steady => 'Steady',
      GrowthSpeed.faster => 'Faster',
      GrowthSpeed.push => 'Push',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        _Handle(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Growth',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Current base plan info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greyBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasBase ? AppColors.border : AppColors.error,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasBase
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_rounded,
                  color: hasBase
                      ? const Color(0xFF16A34A)
                      : AppColors.error,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  hasBase
                      ? 'Current plan: ${base}h/week'
                      : 'Set up a plan first to use Growth',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: hasBase
                        ? AppColors.textDark
                        : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Target
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Target weekly hours',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: !hasBase,
                child: Opacity(
                  opacity: hasBase ? 1.0 : 0.4,
                  child: GestureDetector(
                    onTap: _pickTarget,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: AppColors.greyBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_targetHours}h',
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.edit_outlined,
                              color: AppColors.textLight, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Speed
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Growth speed',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  GrowthSpeed.steady,
                  GrowthSpeed.faster,
                  GrowthSpeed.push,
                ].map((s) {
                  final label = switch (s) {
                    GrowthSpeed.steady => 'Steady\n6 wk',
                    GrowthSpeed.faster => 'Faster\n4 wk',
                    GrowthSpeed.push => 'Push\n2 wk',
                  };
                  final isSelected = _speed == s;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _speed = s),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryBlue
                              : AppColors.greyBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primaryBlue
                                : AppColors.border,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textMedium,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Progress preview
        if (hasBase) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Now: ${base}h',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSlate,
                      ),
                    ),
                    Text(
                      _formatDate(completion),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSlate,
                      ),
                    ),
                    Text(
                      'Goal: ${_targetHours}h',
                      style: GoogleFonts.inter(
                        fontSize: 13,
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
                    value: progressFraction,
                    minHeight: 8,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$totalWeeks weeks · $speedLabel',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSlate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // TODO: "Show weekly details" expandable section

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ElevatedButton(
            onPressed: (!hasBase || _saving) ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.border,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    'Start Growth',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
}
