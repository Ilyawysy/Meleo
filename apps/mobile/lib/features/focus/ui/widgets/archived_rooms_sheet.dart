import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../models/focus_room.dart';
import '../../providers/focus_rooms_provider.dart';
import '../../providers/room_icon_provider.dart';
import '../room_icon_mapper.dart';

class ArchivedRoomsSheet extends ConsumerStatefulWidget {
  const ArchivedRoomsSheet({super.key});

  @override
  ConsumerState<ArchivedRoomsSheet> createState() => _ArchivedRoomsSheetState();
}

class _ArchivedRoomsSheetState extends ConsumerState<ArchivedRoomsSheet> {
  List<FocusRoom> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rooms = await ref.read(archivedRoomsProvider.future);
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    }
  }

  Future<void> _unarchive(FocusRoom room) async {
    await ref.read(focusRoomsProvider.notifier).unarchiveRoom(room.id);
    setState(() {
      _rooms = _rooms.where((r) => r.id != room.id).toList();
    });
  }

  Future<void> _restoreAll() async {
    final rooms = List<FocusRoom>.from(_rooms);
    for (final room in rooms) {
      await ref.read(focusRoomsProvider.notifier).unarchiveRoom(room.id);
    }
    setState(() => _rooms = []);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All rooms restored')),
      );
    }
  }

  String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _duration(int sec) {
    if (sec <= 0) return '0m';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
            const SizedBox(height: 16),

            // Header row with popup menu
            Row(
              children: [
                Text('Archived Rooms', style: AppTypography.heading22()),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'restore_all') _restoreAll();
                    // delete_all is disabled — no action needed
                  },
                  icon: const Icon(Icons.more_vert,
                      size: 20, color: AppColors.textMedium),
                  itemBuilder: (_) => [
                    const PopupMenuItem<String>(
                      value: 'restore_all',
                      child: Text('Restore all'),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete_all',
                      enabled: false,
                      child: Tooltip(
                        message: 'Coming soon',
                        child: Text(
                          'Delete all',
                          style: AppTypography.body14(
                              color: AppColors.textLight),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Body
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_rooms.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'No archived rooms',
                    style: AppTypography.body15(color: AppColors.textMedium),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rooms.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final room = _rooms[i];
                  return Dismissible(
                    key: ValueKey(room.id),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => _unarchive(room),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBlue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.unarchive_outlined,
                          color: Colors.white, size: 22),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.greyBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        leading: _RoomIconWidget(roomId: room.id),
                        title: Text(room.title,
                            style: AppTypography.body15()),
                        subtitle: Text(
                          _subtitle(room),
                          style: AppTypography.caption12(),
                        ),
                        trailing: IconButton(
                          onPressed: () => _unarchive(room),
                          icon: const Icon(
                            Icons.unarchive_outlined,
                            color: AppColors.primaryBlue,
                            size: 20,
                          ),
                          tooltip: 'Restore',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _subtitle(FocusRoom room) {
    final parts = <String>[];
    if (room.archivedAt != null) {
      parts.add('Archived ${_shortDate(room.archivedAt!)}');
    }
    if (room.totalFocusSec > 0) {
      parts.add(_duration(room.totalFocusSec));
    }
    return parts.join(' · ');
  }
}

class _RoomIconWidget extends ConsumerWidget {
  final String roomId;

  const _RoomIconWidget({required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconAsync = ref.watch(roomIconProvider(roomId));
    final icon = iconAsync.valueOrNull;
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: Color(0xFFF2F4F7),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconDataOf(icon),
        size: 18,
        color: AppColors.textSlate,
      ),
    );
  }
}
