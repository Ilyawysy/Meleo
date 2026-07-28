import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../constants/room_icon_colors.dart';
import '../../data/room_icon_db.dart';
import '../../data/task_db.dart';
import '../../data/focus_room_sync_service.dart';
import '../../models/focus_room.dart';
import '../../models/gamification_models.dart';
import '../../models/room_icon.dart';
import '../../models/task.dart';
import '../../providers/focus_rooms_provider.dart';
import '../../providers/room_icon_provider.dart';
import '../room_icon_mapper.dart';

const int _kFallbackDuration = 25;
const int _kFallbackBreak = 5;

class AddRoomSheet extends ConsumerStatefulWidget {
  /// Optional defaults for duration/break. When null, falls back to the
  /// user's gamification profile (focus_duration_min / short_break_min) and
  /// then to 25/5 if the profile has not been loaded yet.
  final GamificationProfile? profile;

  /// When true, the sheet acts as "Start Focus": it creates the room and
  /// returns it via [Navigator.pop] so the caller can immediately start a
  /// session in it. The header and primary button switch to "Start Focus"
  /// wording. When false (default), the sheet just creates the room and
  /// pops with `null`.
  final bool autoStart;

  const AddRoomSheet({super.key, this.profile, this.autoStart = false});

  @override
  ConsumerState<AddRoomSheet> createState() => _AddRoomSheetState();
}

class _AddRoomSheetState extends ConsumerState<AddRoomSheet> {
  final _titleCtrl = TextEditingController();
  RoomIcon _icon = RoomIcon.book;
  bool _checklistExpanded = false;
  final List<TextEditingController> _checklistControllers = [];
  bool _saving = false;
  String? _nameError;

  late int _durationMin;
  late int _breakMin;

  @override
  void initState() {
    super.initState();
    _durationMin = widget.profile?.focusDurationMin ?? _kFallbackDuration;
    _breakMin = widget.profile?.shortBreakMin ?? _kFallbackBreak;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _checklistControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addChecklistItem() {
    setState(() => _checklistControllers.add(TextEditingController()));
  }

  void _removeChecklistItem(int index) {
    _checklistControllers[index].dispose();
    setState(() => _checklistControllers.removeAt(index));
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _nameError = 'Room name is required');
      return;
    }
    setState(() {
      _saving = true;
      _nameError = null;
    });
    try {
      final color = colorForIcon(_icon);
      final newRoom = await ref.read(focusRoomsProvider.notifier).addRoom(
            title: title,
            color: color,
            type: FocusRoomType.regular,
            focusDurationMin: _durationMin,
            breakMin: _breakMin,
          );
      await RoomIconDb().set(newRoom.id, _icon.slug);
      ref.invalidate(roomIconProvider(newRoom.id));

      final items = _checklistControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (items.isNotEmpty) {
        final taskDb = FocusTaskDb();
        for (int i = 0; i < items.length; i++) {
          final task = Task.create(
            roomId: newRoom.id,
            title: items[i],
            sortOrder: i,
          );
          await taskDb.create(task);
        }
        FocusRoomSyncService.instance.scheduleSync();
      }

      if (!mounted) return;
      Navigator.of(context).pop(widget.autoStart ? newRoom : null);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create room: $e')),
        );
      }
    }
  }

  Future<void> _editDuration() async {
    final v = await _showNumberSheet(
      title: 'Duration',
      suffix: 'min',
      initial: _durationMin,
      min: 1,
      max: 240,
    );
    if (v != null) setState(() => _durationMin = v);
  }

  Future<void> _editBreak() async {
    final v = await _showNumberSheet(
      title: 'Break',
      suffix: 'min',
      initial: _breakMin,
      min: 0,
      max: 120,
    );
    if (v != null) setState(() => _breakMin = v);
  }

  Future<int?> _showNumberSheet({
    required String title,
    required String suffix,
    required int initial,
    required int min,
    required int max,
  }) {
    final ctrl = TextEditingController(text: initial.toString());
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: AppTypography.heading18()),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTypography.body17(fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    suffixText: suffix,
                    filled: true,
                    fillColor: AppColors.greyBgDarker,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () {
                      final n = int.tryParse(ctrl.text.trim());
                      if (n == null) return;
                      Navigator.of(ctx).pop(n.clamp(min, max));
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 34,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD4D4D8),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Row(
            children: [
              Text(
                widget.autoStart ? 'Start Focus' : 'Add Room',
                style: AppTypography.heading22(),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F4F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 20,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Name section
          Text(
            'Room name',
            style: AppTypography.body13(color: const Color(0xFF71717A)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            style: AppTypography.body15(),
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
            decoration: InputDecoration(
              hintText: 'e.g. Deep Work',
              hintStyle: AppTypography.body15(color: const Color(0xFFA1A1AA)),
              errorText: _nameError,
              filled: true,
              fillColor: const Color(0xFFF4F4F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.error),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Time card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _TimeRow(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: _durationMin,
                  onTap: _editDuration,
                ),
                const SizedBox(height: 16),
                Container(height: 1, color: const Color(0xFFEBEBEF)),
                const SizedBox(height: 16),
                _TimeRow(
                  icon: Icons.coffee_outlined,
                  label: 'Break',
                  value: _breakMin,
                  onTap: _editBreak,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // + Add checklist toggle (text-only link)
          GestureDetector(
            onTap: () {
              setState(() {
                _checklistExpanded = !_checklistExpanded;
                if (_checklistExpanded && _checklistControllers.isEmpty) {
                  _checklistControllers.add(TextEditingController());
                }
              });
            },
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '+ Add checklist',
                style: AppTypography.body14(
                  color: const Color(0xFF4F46E5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          if (_checklistExpanded) ...[
            const SizedBox(height: 8),
            for (int i = 0; i < _checklistControllers.length; i++) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checklistControllers[i],
                      style: AppTypography.body14(),
                      decoration: InputDecoration(
                        hintText: 'Task item',
                        hintStyle: AppTypography.body14(
                            color: AppColors.textLight),
                        filled: true,
                        fillColor: AppColors.greyBgDarker,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removeChecklistItem(i),
                    icon: const Icon(Icons.close, size: 16),
                    color: AppColors.textLight,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            TextButton.icon(
              onPressed: _addChecklistItem,
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                'Add task',
                style: AppTypography.body13(color: AppColors.primaryBlue),
              ),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          const SizedBox(height: 22),

          // Icon section
          Text(
            'Icon',
            style: AppTypography.body13(color: const Color(0xFF71717A)),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < RoomIcon.values.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                _IconChip(
                  icon: RoomIcon.values[i],
                  selected: _icon == RoomIcon.values[i],
                  onTap: () => setState(() => _icon = RoomIcon.values[i]),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),

          // Create Room button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.autoStart ? 'Start Focus' : 'Create Room',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;

  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFA1A1AA)),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTypography.body14(color: const Color(0xFF71717A)),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value.toString(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'min',
                  style: AppTypography.body13(
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IconChip extends StatelessWidget {
  final RoomIcon icon;
  final bool selected;
  final VoidCallback onTap;

  const _IconChip({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4F46E5) : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          iconDataOf(icon),
          size: 20,
          color: selected ? Colors.white : const Color(0xFF71717A),
        ),
      ),
    );
  }
}
