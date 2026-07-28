import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/design/app_colors.dart';

Future<int?> showHourPicker(
  BuildContext context, {
  required int initial,
  int min = 0,
  int max = 24,
}) async {
  return showModalBottomSheet<int>(
    context: context,
    barrierColor: AppColors.overlay,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _HourPickerSheet(initial: initial, min: min, max: max),
  );
}

class _HourPickerSheet extends StatefulWidget {
  final int initial;
  final int min;
  final int max;

  const _HourPickerSheet({
    required this.initial,
    required this.min,
    required this.max,
  });

  @override
  State<_HourPickerSheet> createState() => _HourPickerSheetState();
}

class _HourPickerSheetState extends State<_HourPickerSheet> {
  late int _selected;
  late FixedExtentScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial.clamp(widget.min, widget.max);
    _ctrl = FixedExtentScrollController(
        initialItem: _selected - widget.min);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.max - widget.min + 1;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Select hours',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  child: Text(
                    'Done',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 200,
            child: CupertinoPicker(
              scrollController: _ctrl,
              itemExtent: 44,
              onSelectedItemChanged: (idx) {
                setState(() => _selected = widget.min + idx);
              },
              children: List.generate(
                count,
                (i) => Center(
                  child: Text(
                    '${widget.min + i}h',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
