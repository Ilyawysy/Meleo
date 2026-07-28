import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/statistics_state.dart';
import '../../providers/statistics_provider.dart';

String _formatDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _weekdayLabel(int weekday) =>
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

Color _parseColor(String hex) {
  try {
    final s = hex.replaceAll('#', '');
    return Color(int.parse('FF$s', radix: 16));
  } catch (_) {
    return const Color(0xFF6366F1);
  }
}

class StatsRoomsPage extends ConsumerWidget {
  const StatsRoomsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(statisticsProvider);
    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Не удалось загрузить')),
      data: (stats) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopStatsRow(
              totalRoomsAll: stats.totalRoomsAll,
              activeRoomsWeek: stats.activeRoomsWeek,
              avgRoomsPerDayWeek: stats.avgRoomsPerDayWeek,
            ),
            const SizedBox(height: 24),
            _TimePerRoomCard(
              roomStatsWeek: stats.roomStatsWeek,
              roomStatsMonth: stats.roomStatsMonth,
            ),
            const SizedBox(height: 24),
            _RoomDetailCard(rooms: stats.roomStatsWeek),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top stats row
// ---------------------------------------------------------------------------

class _TopStatsRow extends StatelessWidget {
  final int totalRoomsAll;
  final int activeRoomsWeek;
  final double avgRoomsPerDayWeek;

  const _TopStatsRow({
    required this.totalRoomsAll,
    required this.activeRoomsWeek,
    required this.avgRoomsPerDayWeek,
  });

  @override
  Widget build(BuildContext context) {
    final avgStr = avgRoomsPerDayWeek.toStringAsFixed(1);
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            value: '$totalRoomsAll',
            valueColor: const Color(0xFF18181B),
            label: 'Total Rooms',
            valueFontSize: 24,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            value: '$activeRoomsWeek',
            valueColor: const Color(0xFF4F46E5),
            label: 'Active',
            valueFontSize: 24,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MiniStatCard(
            value: avgStr,
            valueColor: const Color(0xFF18181B),
            label: 'Avg / day',
            valueFontSize: 24,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Time per Room card
// ---------------------------------------------------------------------------

class _TimePerRoomCard extends StatefulWidget {
  final List<RoomStat> roomStatsWeek;
  final List<RoomStat> roomStatsMonth;

  const _TimePerRoomCard({
    required this.roomStatsWeek,
    required this.roomStatsMonth,
  });

  @override
  State<_TimePerRoomCard> createState() => _TimePerRoomCardState();
}

class _TimePerRoomCardState extends State<_TimePerRoomCard> {
  int _selected = 0; // 0=W, 1=M

  @override
  Widget build(BuildContext context) {
    final rooms = List<RoomStat>.from(
      _selected == 0 ? widget.roomStatsWeek : widget.roomStatsMonth,
    )..sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));
    final topRooms = rooms.take(6).toList();
    final maxMin = topRooms.isEmpty
        ? 1
        : topRooms.first.totalMinutes.clamp(1, double.infinity).toInt();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Time per Room',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF18181B),
                ),
              ),
              _SegmentPill(
                labels: const ['W', 'M'],
                selected: _selected,
                onChanged: (v) => setState(() => _selected = v),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (topRooms.isEmpty)
            Text(
              'No data',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF94A3B8),
              ),
            )
          else
            ...topRooms.asMap().entries.map((entry) {
              final i = entry.key;
              final room = entry.value;
              final barPct = maxMin == 0
                  ? 0.0
                  : (room.totalMinutes / maxMin).clamp(0.0, 1.0);
              final roomColor =
                  _parseColor(room.color).withValues(alpha: i == 0 ? 1.0 : 0.6);

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        room.title,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF18181B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(builder: (ctx, constraints) {
                        final fillW = constraints.maxWidth * barPct;
                        return Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: fillW,
                              height: 14,
                              decoration: BoxDecoration(
                                color: roomColor,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: Text(
                        _formatDuration(room.totalMinutes),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF18181B),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Room Detail card
// ---------------------------------------------------------------------------

class _RoomDetailCard extends StatefulWidget {
  final List<RoomStat> rooms;

  const _RoomDetailCard({required this.rooms});

  @override
  State<_RoomDetailCard> createState() => _RoomDetailCardState();
}

class _RoomDetailCardState extends State<_RoomDetailCard> {
  int _selectedIdx = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.rooms.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(20),
        child: Text(
          'No room data',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: const Color(0xFF94A3B8),
          ),
        ),
      );
    }

    final rooms = widget.rooms;
    final room = rooms[_selectedIdx % rooms.length];
    final roomColor = _parseColor(room.color);
    final now = DateTime.now();
    final todayWd = now.weekday;

    int maxDayMin = 1;
    for (int d = 1; d <= 7; d++) {
      final v = room.dailyMinutes[d] ?? 0;
      if (v > maxDayMin) maxDayMin = v;
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Room selector
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => setState(() =>
                    _selectedIdx =
                        (_selectedIdx - 1 + rooms.length) % rooms.length),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_left,
                      size: 16, color: Color(0xFF18181B)),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: roomColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    room.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF18181B),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => setState(
                    () => _selectedIdx = (_selectedIdx + 1) % rooms.length),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFF18181B)),
                ),
              ),
            ],
          ),
          // Mini metrics
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CompactMetric(
                  value: '${(room.allFocusPct * 100).round()}%',
                  label: 'All Focus %',
                  valueColor: const Color(0xFF4F46E5),
                ),
                _CompactMetric(
                  value: _formatDuration(room.totalMinutes),
                  label: 'Total',
                  valueColor: const Color(0xFF18181B),
                ),
                _CompactMetric(
                  value: '${room.totalSessions}',
                  label: 'Sessions',
                  valueColor: const Color(0xFF18181B),
                ),
                _CompactMetric(
                  value:
                      '${room.avgSessionMinutes.round()}m',
                  label: 'Avg / s',
                  valueColor: const Color(0xFF18181B),
                ),
              ],
            ),
          ),
          // Daily bars
          SizedBox(
            height: 84,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(7, (idx) {
                  final wd = idx + 1;
                  final val = room.dailyMinutes[wd] ?? 0;
                  final isToday = wd == todayWd;
                  final isFuture = wd > todayWd;
                  final barH = maxDayMin == 0
                      ? 4.0
                      : (val / maxDayMin * 56).clamp(4.0, 56.0);
                  final barColor = (val == 0 || isFuture)
                      ? const Color(0xFFE5E7EB)
                      : isToday
                          ? roomColor
                          : roomColor.withValues(alpha: 0.6);

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 16,
                        height: barH,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _weekdayLabel(wd).substring(0, 2),
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isToday
                              ? roomColor
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Best time pill
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department,
                        size: 16, color: Color(0xFF4F46E5)),
                    const SizedBox(width: 8),
                    Text(
                      'Best Time in Room',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
                Text(
                  room.bestWindow,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF4F46E5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _MiniStatCard extends StatelessWidget {
  final String value;
  final Color valueColor;
  final String label;
  final double valueFontSize;

  const _MiniStatCard({
    required this.value,
    required this.valueColor,
    required this.label,
    this.valueFontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8FA),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: valueFontSize,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _CompactMetric({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _SegmentPill extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const _SegmentPill({
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final isActive = i == selected;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                labels[i],
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive
                      ? const Color(0xFF18181B)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
