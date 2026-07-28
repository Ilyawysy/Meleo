import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../providers/adaptive_plan_provider.dart';
import 'shared/hour_picker.dart';

const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _dayShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class PlanSetupSheet extends ConsumerStatefulWidget {
  const PlanSetupSheet({super.key});

  @override
  ConsumerState<PlanSetupSheet> createState() => _PlanSetupSheetState();
}

class _PlanSetupSheetState extends ConsumerState<PlanSetupSheet> {
  late List<int> _hours;
  bool _sameForAll = true;
  int _sameHours = 2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final plan = ref.read(adaptivePlanProvider).valueOrNull;
    final init = plan?.hoursPerDay;
    if (init != null && init.length == 7) {
      _hours = List<int>.from(init);
      final allSame = init.toSet().length <= 1;
      _sameForAll = allSame;
      _sameHours = init.first;
    } else {
      _hours = [2, 2, 2, 2, 2, 0, 0];
      _sameForAll = false;
    }
  }

  List<bool> get _activeDays => _hours.map((h) => h > 0).toList();

  int get _total => _hours.fold(0, (s, h) => s + h);

  void _toggleDay(int idx) {
    setState(() {
      if (_hours[idx] > 0) {
        _hours[idx] = 0;
      } else {
        _hours[idx] = _sameForAll ? _sameHours : 2;
      }
    });
  }

  Future<void> _pickHourForDay(int idx) async {
    final picked = await showHourPicker(
      context,
      initial: _hours[idx] > 0 ? _hours[idx] : 1,
      min: 1,
      max: 16,
    );
    if (picked != null && mounted) {
      setState(() => _hours[idx] = picked);
    }
  }

  Future<void> _pickSameHour() async {
    final picked = await showHourPicker(
      context,
      initial: _sameHours,
      min: 1,
      max: 16,
    );
    if (picked != null && mounted) {
      setState(() {
        _sameHours = picked;
        for (int i = 0; i < 7; i++) {
          if (_hours[i] > 0) _hours[i] = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(adaptivePlanProvider.notifier).setupPlan(_hours);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
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
                'Custom Plan',
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
        const SizedBox(height: 20),

        // Focus Days chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Focus Days',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (i) => _DayToggleChip(
                  label: _dayShort[i],
                  active: _hours[i] > 0,
                  onTap: () => _toggleDay(i),
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Segmented toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _SegmentToggle(
            options: const ['Same for all', 'Custom'],
            selected: _sameForAll ? 0 : 1,
            onChanged: (idx) {
              setState(() => _sameForAll = idx == 0);
            },
          ),
        ),
        const SizedBox(height: 20),

        if (_sameForAll) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hours per focus day',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSlate,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickSameHour,
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
                          '${_sameHours}h',
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
              ],
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: List.generate(7, (i) {
                if (!_activeDays[i]) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onTap: () => _pickHourForDay(i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.greyBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Text(
                            _dayLabels[i],
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textDark,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_hours[i]}h',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: AppColors.textLight, size: 18),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                'Total per week:',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_total}h',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
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
                    'Save Plan',
                    style: GoogleFonts.inter(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'You can change this anytime',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.textLight,
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

class _DayToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _DayToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryBlue : AppColors.greyBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.textMedium,
          ),
        ),
      ),
    );
  }
}

class _SegmentToggle extends StatelessWidget {
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  const _SegmentToggle({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(options.length, (i) {
          final isSelected = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  options[i],
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? AppColors.textDark
                        : AppColors.textMedium,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
