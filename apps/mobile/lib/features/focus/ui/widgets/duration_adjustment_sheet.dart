import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';

class DurationAdjustmentSheet extends StatefulWidget {
  final int actualElapsedSec;
  final String? taskTitle;

  const DurationAdjustmentSheet({
    super.key,
    required this.actualElapsedSec,
    this.taskTitle,
  });

  @override
  State<DurationAdjustmentSheet> createState() => _DurationAdjustmentSheetState();
}

class _DurationAdjustmentSheetState extends State<DurationAdjustmentSheet> {
  late int _creditedMinutes;

  int get _maxMinutes => (widget.actualElapsedSec / 60).floor();

  @override
  void initState() {
    super.initState();
    _creditedMinutes = _maxMinutes;
  }

  String _fmtSec(int s) {
    final d = Duration(seconds: s);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sc = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$sc' : '$m:$sc';
  }

  Widget _buildHandleBar() {
    return Center(
      child: Container(
        width: 40,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD4D4D8),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(icon, size: 16, color: AppColors.textDark),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandleBar(),
            const SizedBox(height: 20),
            Text('Adjust Duration', style: AppTypography.heading22()),
            const SizedBox(height: 12),
            Text(
              'Your focus session lasted ${_fmtSec(widget.actualElapsedSec).split(':')[0]} minutes. Adjust the credited time if needed.',
              style: AppTypography.body15(color: AppColors.textMedium).copyWith(height: 1.4),
            ),
            const SizedBox(height: 24),
            Center(
              child: Column(
                children: [
                  Text(
                    _fmtSec(widget.actualElapsedSec),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      letterSpacing: -2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('actual time', style: AppTypography.body14(color: AppColors.textLight)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Credited minutes', style: AppTypography.body13()),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.greyBg,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _buildCircleButton(Icons.remove, () {
                    setState(() {
                      final next = _creditedMinutes - 5;
                      _creditedMinutes = next < 0 ? 0 : next;
                    });
                  }),
                  Expanded(
                    child: Center(
                      child: Text(
                        '$_creditedMinutes',
                        style: AppTypography.body15(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),
                  _buildCircleButton(Icons.add, () {
                    setState(() {
                      final next = _creditedMinutes + 5;
                      _creditedMinutes = next > _maxMinutes ? _maxMinutes : next;
                    });
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the number to enter exact value. Buttons adjust by 5 minutes.',
              style: AppTypography.caption12(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(_creditedMinutes * 60),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Save',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
