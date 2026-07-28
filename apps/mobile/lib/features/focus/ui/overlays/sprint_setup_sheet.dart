import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../models/focus_room.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/adaptive_plan_provider.dart';
import '../../providers/focus_rooms_provider.dart';

class SprintSetupSheet extends ConsumerStatefulWidget {
  const SprintSetupSheet({super.key});

  @override
  ConsumerState<SprintSetupSheet> createState() => _SprintSetupSheetState();
}

class _SprintSetupSheetState extends ConsumerState<SprintSetupSheet> {
  final _goalCtrl = TextEditingController();
  int _totalHours = 20;
  DateTime _deadline = DateTime.now().add(const Duration(days: 14));
  bool _saving = false;
  String? _goalError;

  @override
  void dispose() {
    _goalCtrl.dispose();
    super.dispose();
  }

  int get _daysLeft =>
      _deadline.difference(DateTime.now()).inDays.clamp(0, 9999);

  // Estimate active focus days from plan (days where hours > 0).
  // Falls back to 5 (standard work week) when plan is absent or all zeros.
  int get _focusDaysPerWeek {
    final plan = ref.read(adaptivePlanProvider).valueOrNull;
    final hours = plan?.hoursPerDay;
    if (hours == null) return 5;
    final count = hours.where((h) => h > 0).length;
    return count > 0 ? count : 5;
  }

  bool get _usingFallbackDays {
    final plan = ref.read(adaptivePlanProvider).valueOrNull;
    final hours = plan?.hoursPerDay;
    if (hours == null) return true;
    return hours.every((h) => h == 0);
  }

  double get _avgDailyHours {
    final focusDays = _daysLeft * _focusDaysPerWeek / 7;
    if (focusDays <= 0) return 0;
    return _totalHours / focusDays;
  }

  bool get _isIntense => _avgDailyHours > 8;

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_deadline),
    );
    if (time == null || !mounted) return;
    setState(() {
      _deadline = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    final goal = _goalCtrl.text.trim();
    if (goal.isEmpty) {
      setState(() => _goalError = 'Enter a goal');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(focusRoomsProvider.notifier).addRoom(
        title: goal,
        color: '#F59E0B',
        type: FocusRoomType.sprint,
        sprintGoal: goal,
        sprintDeadline: _deadline,
        sprintTotalHours: _totalHours,
      );
      // Select the newly created sprint room
      final rooms = ref.read(focusRoomsProvider).valueOrNull ?? [];
      final sprint = rooms
          .cast<FocusRoom?>()
          .lastWhere(
            (r) => r!.type == FocusRoomType.sprint && !r.archived,
            orElse: () => null,
          );
      if (sprint != null) {
        await ref.read(activeRoomIdProvider.notifier).set(sprint.id);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
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
    final dateLabel = _formatDate(_deadline);
    final timeLabel = _formatTime(_deadline);
    final avgStr = _avgDailyHours.toStringAsFixed(1);
    final showFallbackHint = _usingFallbackDays;

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
                'Sprint',
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

        // Goal input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What do you need to focus on?',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _goalCtrl,
                onChanged: (_) {
                  if (_goalError != null) setState(() => _goalError = null);
                },
                decoration: InputDecoration(
                  hintText: 'Prepare for exam',
                  hintStyle: GoogleFonts.inter(
                      fontSize: 15, color: AppColors.textLight),
                  errorText: _goalError,
                  filled: true,
                  fillColor: AppColors.greyBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primaryBlue),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                style: GoogleFonts.inter(
                    fontSize: 15, color: AppColors.textDark),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Total hours
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total focus hours needed',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      if (_totalHours > 1) {
                        setState(() => _totalHours--);
                      }
                    },
                    icon: const Icon(Icons.remove_circle_outline),
                    color: AppColors.primaryBlue,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_totalHours}h',
                        style: GoogleFonts.inter(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _totalHours++),
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppColors.primaryBlue,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Deadline
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Deadline',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSlate,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _pickDeadline,
                child: Row(
                  children: [
                    _Chip(label: dateLabel, icon: Icons.calendar_today_outlined),
                    const SizedBox(width: 8),
                    _Chip(label: timeLabel, icon: Icons.access_time_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Daily breakdown card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isIntense
                  ? const Color(0xFFFFF7ED)
                  : AppColors.greyBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isIntense
                    ? const Color(0xFFFDE68A)
                    : AppColors.border,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (_isIntense)
                      const Icon(Icons.warning_amber_rounded,
                          color: Color(0xFFD97706), size: 16),
                    if (_isIntense) const SizedBox(width: 6),
                    Text(
                      _isIntense ? 'Intense schedule' : 'Daily breakdown',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _isIntense
                            ? const Color(0xFFD97706)
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _BreakdownRow(label: 'Days left', value: '$_daysLeft'),
                _BreakdownRow(
                    label: 'Avg per focus day', value: '${avgStr}h'),
                _BreakdownRow(
                    label: 'Total sprint hours', value: '${_totalHours}h'),
                if (showFallbackHint) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Estimated assuming 5 focus days/week',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Save button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
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
                    'Create Sprint Room',
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

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _Chip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSlate),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;

  const _BreakdownRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSlate,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
        ],
      ),
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

String _formatTime(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour < 12 ? 'AM' : 'PM';
  return '$h:$m $period';
}
