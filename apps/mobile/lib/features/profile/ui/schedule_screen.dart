import 'package:flutter/material.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../focus/data/focus_db.dart';
import '../../focus/data/focus_sync_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _goalPresets = [0, 30, 60, 90, 120];

  Map<int, int> _planMinutes = {1: 60, 2: 60, 3: 60, 4: 60, 5: 60, 6: 0, 7: 0};
  int _applyAllValue = 60;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await FocusDb().getProfile();
    if (!mounted) return;
    setState(() {
      if (profile != null) {
        _planMinutes = Map<int, int>.from(profile.planMinutes);
      }
      // fill missing days
      for (int d = 1; d <= 7; d++) {
        _planMinutes.putIfAbsent(d, () => 0);
      }
      _loaded = true;
    });
  }

  Future<void> _save() async {
    await FocusDb().setPendingProfileSettings(planMinutes: _planMinutes);
    FocusSyncService.instance.scheduleSync();
  }

  void _tapDay(int day) {
    _showGoalPicker(
      currentValue: _planMinutes[day] ?? 0,
      onSelected: (value) {
        setState(() => _planMinutes[day] = value);
        _save();
      },
    );
  }

  void _tapApplyAll() {
    _showGoalPicker(
      currentValue: _applyAllValue,
      onSelected: (value) {
        setState(() {
          _applyAllValue = value;
          for (int d = 1; d <= 7; d++) {
            _planMinutes[d] = value;
          }
        });
        _save();
      },
    );
  }

  void _showGoalPicker({required int currentValue, required ValueChanged<int> onSelected}) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set Goal', style: AppTypography.heading18()),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _goalPresets.map((mins) {
                  final isSelected = mins == currentValue;
                  final label = mins == 0 ? 'Off' : '$mins min';
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(mins);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primaryBlue : AppColors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primaryBlue : AppColors.border,
                        ),
                      ),
                      child: Text(
                        label,
                        style: AppTypography.body14(
                          color: isSelected ? Colors.white : AppColors.textDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            // Nav
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _backButton(),
                  Text('Schedule', style: AppTypography.heading18()),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Set your focus goals for each day of the week.',
              style: AppTypography.body14(color: AppColors.textMedium),
            ),
            const SizedBox(height: 20),

            // Days card
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.greyBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  for (int d = 1; d <= 7; d++) ...[
                    if (d > 1) Container(height: 1, color: AppColors.divider),
                    _dayRow(d),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Apply to all row
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _tapApplyAll,
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Apply to all days',
                      style: AppTypography.body14(fontWeight: FontWeight.w500),
                    ),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD4D4D8), width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.access_time, size: 16, color: AppColors.primaryBlue),
                          const SizedBox(width: 6),
                          Text(
                            '$_applyAllValue min',
                            style: AppTypography.body14(
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.keyboard_arrow_down,
                              size: 14, color: AppColors.textSlateLight),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(int day) {
    final mins = _planMinutes[day] ?? 0;
    final isOff = mins == 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapDay(day),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOff ? AppColors.textLight : AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _dayNames[day - 1],
                style: AppTypography.body15(fontWeight: FontWeight.w500),
              ),
            ),
            if (isOff)
              Text('Off', style: AppTypography.body14(color: AppColors.textLight))
            else
              Text(
                '$mins min',
                style: AppTypography.body14(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _backButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.greyBgDarker,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.arrow_back, size: 20, color: AppColors.textDark),
      ),
    );
  }
}
