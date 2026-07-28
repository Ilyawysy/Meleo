import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../models/checklist_item.dart';
import '../../models/focus_room.dart';
import '../../models/task.dart';
import '../../models/focus_models.dart';
import 'mascot.dart';
import 'timer_ring.dart';

class FocusSessionView extends StatefulWidget {
  final FocusSession session;
  final Task? task;
  final String remainingLabel;
  final int activeElapsedSec;
  final bool isStopwatch;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onCancel;
  final VoidCallback onFinish;
  final VoidCallback onChangeTask;
  final List<ChecklistItem> checklistItems;
  final ValueChanged<ChecklistItem>? onToggleChecklist;
  final VoidCallback? onBack;

  /// Room-driven session mode. When [room] is non-null the task card is
  /// replaced with an editable room-title card + a checklist of the room's
  /// own tasks (see [roomTasks]). This is used when the user starts a focus
  /// session by opening a Focus Room from the Start tab.
  final FocusRoom? room;
  final List<Task> roomTasks;
  final ValueChanged<Task>? onToggleRoomTask;
  final ValueChanged<String>? onAddRoomTask;
  final ValueChanged<String>? onRenameRoom;

  const FocusSessionView({
    super.key,
    required this.session,
    required this.task,
    required this.remainingLabel,
    required this.activeElapsedSec,
    this.isStopwatch = false,
    required this.onPlay,
    required this.onPause,
    required this.onCancel,
    required this.onFinish,
    required this.onChangeTask,
    required this.checklistItems,
    this.onToggleChecklist,
    this.onBack,
    this.room,
    this.roomTasks = const [],
    this.onToggleRoomTask,
    this.onAddRoomTask,
    this.onRenameRoom,
  });

  @override
  State<FocusSessionView> createState() => _FocusSessionViewState();
}

class _FocusSessionViewState extends State<FocusSessionView> {
  late final TextEditingController _roomNameCtrl;
  final _addTaskCtrl = TextEditingController();
  bool _showAddTask = false;

  @override
  void initState() {
    super.initState();
    _roomNameCtrl = TextEditingController(text: widget.room?.title ?? '');
  }

  @override
  void didUpdateWidget(covariant FocusSessionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the room-name field in sync when the parent swaps the room or
    // a remote update renames it.
    final newTitle = widget.room?.title ?? '';
    if (oldWidget.room?.title != widget.room?.title &&
        _roomNameCtrl.text != newTitle) {
      _roomNameCtrl.text = newTitle;
    }
  }

  @override
  void dispose() {
    _roomNameCtrl.dispose();
    _addTaskCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final isRunning = widget.session.status == FocusSessionStatus.running;
    final isCreated = widget.session.status == FocusSessionStatus.created;
    final isPaused = widget.session.status == FocusSessionStatus.paused;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onBack != null) ...[
            Row(
              children: [
                GestureDetector(
                  onTap: widget.onBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.greyBgDarker,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      size: 24,
                      color: AppColors.textMedium,
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 8),
          ],
          widget.isStopwatch
              ? _buildStopwatchLayout(context, isRunning, isCreated, isPaused)
              : _buildTimerLayout(context, isRunning, isCreated, isPaused),
        ],
      ),
    );
  }

  Widget _buildTimerLayout(BuildContext context, bool isRunning, bool isCreated, bool isPaused) {
    final plannedSec = widget.session.plannedDurationSec;
    final progress = plannedSec > 0
        ? (1.0 - widget.activeElapsedSec / plannedSec).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            widget.room?.title ?? 'Focus',
            style: AppTypography.body13(),
          ),
        ),
        const SizedBox(height: 12),
        const Center(child: Mascot(mode: MascotMode.focus, size: 260)),
        const SizedBox(height: 16),
        Center(
          child: TimerRing(
            progress: progress,
            size: 240,
            child: _timerLabel(isPaused),
          ),
        ),
        const SizedBox(height: 24),
        widget.room != null ? _buildRoomCard() : _buildTaskCard(),
        const SizedBox(height: 24),
        _buildTimerControls(isRunning, isCreated, isPaused),
      ],
    );
  }

  Widget _timerLabel(bool isPaused) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.remainingLabel,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 44,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
            letterSpacing: -1.5,
          ),
        ),
        Text(
          isPaused ? 'paused' : 'remaining',
          style: AppTypography.body13(),
        ),
      ],
    );
  }

  Widget _buildStopwatchLayout(BuildContext context, bool isRunning, bool isCreated, bool isPaused) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text('Stopwatch mode', style: AppTypography.body13()),
        ),
        const SizedBox(height: 12),
        const Center(child: Mascot(mode: MascotMode.focus, size: 280)),
        const SizedBox(height: 16),
        Center(
          child: Text(
            widget.remainingLabel,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 72,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
              letterSpacing: -3,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'elapsed',
            style: AppTypography.body14(color: AppColors.textMedium),
          ),
        ),
        const SizedBox(height: 24),
        widget.room != null ? _buildRoomCard() : _buildTaskCard(),
        const SizedBox(height: 24),
        _buildStopwatchControls(isRunning, isCreated, isPaused),
      ],
    );
  }

  // ───────────────── Room card (session opened from a Focus Room) ─────────
  Widget _buildRoomCard() {
    final tasks = widget.roomTasks;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _roomNameCtrl,
            style: AppTypography.body15(fontWeight: FontWeight.w700),
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              hintText: 'Room name',
            ),
            onSubmitted: (v) {
              final trimmed = v.trim();
              if (trimmed.isNotEmpty) widget.onRenameRoom?.call(trimmed);
            },
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          if (tasks.isEmpty && !_showAddTask)
            Text(
              'No tasks yet.',
              style: AppTypography.body13(color: AppColors.textMedium),
            ),
          for (final t in tasks) _buildRoomTaskRow(t),
          if (_showAddTask)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: TextField(
                controller: _addTaskCtrl,
                autofocus: true,
                style: AppTypography.body14(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'New task title',
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: const UnderlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    onPressed: _submitNewTask,
                  ),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitNewTask(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: GestureDetector(
                onTap: () => setState(() => _showAddTask = true),
                child: Text(
                  '+ Add task',
                  style: AppTypography.body13(color: AppColors.primaryBlue),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomTaskRow(Task t) {
    final done = t.isDone;
    return InkWell(
      onTap: () => widget.onToggleRoomTask?.call(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: done,
                onChanged: (_) => widget.onToggleRoomTask?.call(t),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                t.title,
                style: done
                    ? AppTypography.body14(color: AppColors.textLight).copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : AppTypography.body14(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitNewTask() {
    final title = _addTaskCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _showAddTask = false);
      return;
    }
    widget.onAddRoomTask?.call(title);
    _addTaskCtrl.clear();
    setState(() => _showAddTask = false);
  }

  Widget _buildTaskCard() {
    const maxVisible = 3;
    final visible = widget.checklistItems.take(maxVisible).toList();
    final remaining = widget.checklistItems.length - maxVisible;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.task?.title ?? 'Free focus (no task)',
                  style: AppTypography.body15(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onChangeTask,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.swap_horiz, size: 14, color: AppColors.textMedium),
                      const SizedBox(width: 4),
                      Text('Switch', style: AppTypography.caption12(color: AppColors.textMedium)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (visible.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
            ...visible.map((item) => _buildChecklistItem(item)),
            if (remaining > 0) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: widget.onChangeTask,
                child: Text(
                  '+ $remaining more items',
                  style: AppTypography.body13(color: AppColors.primaryBlue),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildChecklistItem(ChecklistItem item) {
    return InkWell(
      onTap: () => widget.onToggleChecklist?.call(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: item.isDone,
                onChanged: (_) => widget.onToggleChecklist?.call(item),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.primaryBlue,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.title,
                style: item.isDone
                    ? AppTypography.body14(color: AppColors.textLight).copyWith(
                        decoration: TextDecoration.lineThrough,
                      )
                    : AppTypography.body14(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimerControls(bool isRunning, bool isCreated, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () => _showCancelDialog(context),
          child: Text('Cancel', style: AppTypography.body15(color: AppColors.textMedium)),
        ),
        const SizedBox(width: 32),
        if (isRunning)
          _buildGradientCircleButton(
            size: 68,
            icon: Icons.pause,
            iconSize: 28,
            onTap: widget.onPause,
          ),
        if (isCreated || isPaused)
          _buildGradientCircleButton(
            size: 68,
            icon: Icons.play_arrow_rounded,
            iconSize: 28,
            onTap: widget.onPlay,
          ),
        const SizedBox(width: 16),
        if (isRunning || isPaused)
          _buildSolidCircleButton(
            size: 56,
            icon: Icons.stop_rounded,
            iconSize: 24,
            color: const Color(0xFF16A34A),
            onTap: widget.onFinish,
          ),
      ],
    );
  }

  Widget _buildStopwatchControls(bool isRunning, bool isCreated, bool isPaused) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLabeledCircleButton(
          size: 52,
          icon: Icons.close,
          iconColor: AppColors.textMedium,
          label: 'Cancel',
          labelColor: AppColors.textMedium,
          outlined: true,
          onTap: () => _showCancelDialog(context),
        ),
        const SizedBox(width: 24),
        if (isRunning)
          _buildLabeledCircleButton(
            size: 68,
            icon: Icons.pause,
            iconColor: AppColors.white,
            label: 'Pause',
            labelColor: AppColors.primaryBlue,
            gradient: true,
            onTap: widget.onPause,
          ),
        if (isCreated || isPaused)
          _buildLabeledCircleButton(
            size: 68,
            icon: Icons.play_arrow_rounded,
            iconColor: AppColors.white,
            label: 'Play',
            labelColor: AppColors.primaryBlue,
            gradient: true,
            onTap: widget.onPlay,
          ),
        const SizedBox(width: 24),
        if (isRunning || isPaused)
          _buildLabeledCircleButton(
            size: 52,
            icon: Icons.stop_rounded,
            iconColor: AppColors.white,
            label: 'Finish',
            labelColor: const Color(0xFF16A34A),
            solidColor: const Color(0xFF16A34A),
            onTap: widget.onFinish,
          ),
        if (isCreated)
          _buildLabeledCircleButton(
            size: 52,
            icon: Icons.stop_rounded,
            iconColor: AppColors.white,
            label: 'Finish',
            labelColor: AppColors.textLight,
            solidColor: AppColors.textLight,
            onTap: null,
          ),
      ],
    );
  }

  Widget _buildGradientCircleButton({
    required double size,
    required IconData icon,
    required double iconSize,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.white, size: iconSize),
      ),
    );
  }

  Widget _buildSolidCircleButton({
    required double size,
    required IconData icon,
    required double iconSize,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.white, size: iconSize),
      ),
    );
  }

  Widget _buildLabeledCircleButton({
    required double size,
    required IconData icon,
    required Color iconColor,
    required String label,
    required Color labelColor,
    bool outlined = false,
    bool gradient = false,
    Color? solidColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: gradient
                  ? const LinearGradient(
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
                    )
                  : null,
              color: solidColor,
              shape: BoxShape.circle,
              border: outlined
                  ? Border.all(color: AppColors.border, width: 1.5)
                  : null,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.4),
          ),
          const SizedBox(height: 6),
          Text(label, style: AppTypography.caption12(color: labelColor)),
        ],
      ),
    );
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cancel session?', style: AppTypography.heading20()),
                const SizedBox(height: 8),
                Text(
                  'Your progress won\'t be saved.',
                  style: AppTypography.body15(color: AppColors.textMedium),
                ),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Continue session',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.onCancel();
                  },
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Cancel session',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
