import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../data/task_db.dart';
import '../../models/task.dart';

class SwitchTaskSheet extends StatefulWidget {
  final Task? currentTask;
  final int elapsedSec;
  final String? roomId;

  const SwitchTaskSheet({
    super.key,
    required this.currentTask,
    required this.elapsedSec,
    this.roomId,
  });

  @override
  State<SwitchTaskSheet> createState() => _SwitchTaskSheetState();
}

class _SwitchTaskSheetState extends State<SwitchTaskSheet> {
  Task? _newTask;
  bool _showPicker = false;

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

  @override
  Widget build(BuildContext context) {
    final currentTitle = widget.currentTask?.title ?? 'Free focus';
    final timeStr = _fmtSec(widget.elapsedSec);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHandleBar(),
            const SizedBox(height: 20),
            Text('Switch task?', style: AppTypography.heading22()),
            const SizedBox(height: 12),
            Text(
              'Time already tracked ($timeStr) will be saved to $currentTitle.',
              style: AppTypography.body15(color: AppColors.textMedium)
                  .copyWith(height: 1.4),
            ),
            const SizedBox(height: 20),
            Text('Select new task', style: AppTypography.body13()),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _showPicker = !_showPicker),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.greyBgDarker,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _newTask?.title ?? 'Free focus (no task)',
                        style: AppTypography.body15(
                          color: _newTask != null
                              ? AppColors.textDark
                              : AppColors.textLight,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down,
                        color: AppColors.textMedium, size: 20),
                  ],
                ),
              ),
            ),
            if (_showPicker) ...[
              const SizedBox(height: 8),
              _InlineTaskPicker(
                selected: _newTask,
                roomId: widget.roomId,
                onSelected: (task) {
                  setState(() {
                    _newTask = task;
                    _showPicker = false;
                  });
                },
              ),
            ],
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(_newTask),
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
                  'Switch',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                child: Text('Cancel',
                    style: AppTypography.body15(color: AppColors.textMedium)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineTaskPicker extends StatefulWidget {
  final Task? selected;
  final String? roomId;
  final ValueChanged<Task?> onSelected;

  const _InlineTaskPicker({
    required this.selected,
    required this.onSelected,
    this.roomId,
  });

  @override
  State<_InlineTaskPicker> createState() => _InlineTaskPickerState();
}

class _InlineTaskPickerState extends State<_InlineTaskPicker> {
  bool _loading = true;
  List<Task> _results = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<Task> items;
      if (widget.roomId != null) {
        items = await FocusTaskDb().listForRoom(widget.roomId!);
      } else {
        items = [];
      }
      if (!mounted) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          dense: true,
          title:
              Text('Free focus (no task)', style: AppTypography.body14()),
          contentPadding: EdgeInsets.zero,
          onTap: () => widget.onSelected(null),
        ),
        if (_results.isNotEmpty)
          SizedBox(
            height: 160,
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final item = _results[index];
                return ListTile(
                  dense: true,
                  title: Text(item.title, style: AppTypography.body14()),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => widget.onSelected(item),
                );
              },
            ),
          ),
      ],
    );
  }
}
