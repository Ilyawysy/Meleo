import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../../core/sync/first_sync_settled_provider.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/focus_provider.dart';
import '../../providers/focus_rooms_provider.dart';
import '../widgets/add_room_sheet.dart';
import '../widgets/archived_rooms_sheet.dart';
import '../widgets/room_card.dart';

class RoomsSection extends ConsumerWidget {
  final VoidCallback onRoomSelected;

  const RoomsSection({super.key, required this.onRoomSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(focusRoomsProvider);
    final firstSyncSettled = ref.watch(firstSyncSettledProvider);

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text(
                  'Rooms',
                  style: AppTypography.heading18(),
                ),
                const Spacer(),
                _HeaderIconBtn(
                  icon: Icons.inventory_2_outlined,
                  tooltip: 'Archived',
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    barrierColor: AppColors.overlay,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => const ArchivedRoomsSheet(),
                  ),
                ),
                const SizedBox(width: 8),
                _HeaderIconBtn(
                  icon: Icons.add,
                  tooltip: 'Add room',
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    barrierColor: AppColors.overlay,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    builder: (_) => AddRoomSheet(
                      profile: ref.read(focusProvider)?.profile,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Body
          roomsAsync.when(
            loading: () => const _RoomsSkeleton(),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Error: $e',
                style: AppTypography.body14(color: AppColors.error),
              ),
            ),
            data: (rooms) {
              if (rooms.isEmpty && !firstSyncSettled) {
                return const _RoomsSkeleton();
              }
              if (rooms.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text(
                    'No rooms yet. Tap + to create one.',
                    style: AppTypography.body14(color: AppColors.textMedium),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    for (int i = 0; i < rooms.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Dismissible(
                        key: ValueKey(rooms[i].id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Archive room?'),
                              content: Text(
                                  'Archive "${rooms[i].title}"? You can restore it later.'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(ctx).pop(true),
                                  child: const Text('Archive'),
                                ),
                              ],
                            ),
                          ) ??
                              false;
                        },
                        onDismissed: (_) {
                          ref
                              .read(focusRoomsProvider.notifier)
                              .archiveRoom(rooms[i].id);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.archive_outlined,
                              color: Colors.white, size: 24),
                        ),
                        child: RoomCard(
                          room: rooms[i],
                          onTap: () {
                            ref
                                .read(activeRoomIdProvider.notifier)
                                .set(rooms[i].id);
                            onRoomSelected();
                          },
                          onArchive: () {
                            ref
                                .read(focusRoomsProvider.notifier)
                                .archiveRoom(rooms[i].id);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoomsSkeleton extends StatelessWidget {
  const _RoomsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        children: [
          for (int i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Container(
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.greyBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Icon(icon, size: 18, color: AppColors.textSlate),
        ),
      ),
    );
  }
}
