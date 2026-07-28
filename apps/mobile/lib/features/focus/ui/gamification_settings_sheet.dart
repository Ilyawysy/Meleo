import 'package:flutter/material.dart';
import '../data/focus_db.dart';
import '../data/focus_sync_service.dart';
import '../models/gamification_models.dart';

class GamificationSettingsSheet extends StatefulWidget {
  final GamificationProfile profile;

  const GamificationSettingsSheet({
    super.key,
    required this.profile,
  });

  @override
  State<GamificationSettingsSheet> createState() =>
      _GamificationSettingsSheetState();
}

class _GamificationSettingsSheetState
    extends State<GamificationSettingsSheet> {
  late Map<int, int> _planMinutes;
  late int _dayCutoffHour;
  bool _saving = false;

  static const _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  void initState() {
    super.initState();
    _planMinutes = Map.from(widget.profile.planMinutes);
    _dayCutoffHour = widget.profile.dayCutoffHour;
  }

  bool _isDayEnabled(int weekday) => (_planMinutes[weekday] ?? 0) > 0;

  void _toggleDay(int weekday) {
    setState(() {
      if (_isDayEnabled(weekday)) {
        _planMinutes[weekday] = 0;
      } else {
        _planMinutes[weekday] = 30;
      }
    });
  }

  int _enabledDaysCount() =>
      _planMinutes.values.where((v) => v > 0).length;

  Future<void> _save() async {
    if (_enabledDaysCount() == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы один день')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final db = FocusDb();
      await db.setPendingProfileSettings(
        planMinutes: _planMinutes,
        dayCutoffHour: _dayCutoffHour,
      );
      final updated = await db.getProfile();
      if (!mounted) return;
      Navigator.of(context).pop(updated);
      await FocusSyncService.instance.pushDirtyOnly();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Настройки', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),

              // Per-day plan minutes
              Text('Цель по дням', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ...List.generate(7, (i) {
                final weekday = i + 1;
                final enabled = _isDayEnabled(weekday);
                final minutes = _planMinutes[weekday] ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            _dayLabels[i],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: enabled,
                          onChanged: (_) => _toggleDay(weekday),
                        ),
                        if (enabled) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: Slider(
                              value: minutes.toDouble(),
                              min: 10,
                              max: 480,
                              divisions: 47,
                              label: '$minutes мин',
                              onChanged: (v) {
                                setState(() {
                                  _planMinutes[weekday] =
                                      (v / 10).round() * 10;
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              '$minutes мин',
                              style: theme.textTheme.bodySmall,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ] else
                          Expanded(
                            child: Text(
                              'Не учитывается',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              }),
              const SizedBox(height: 12),

              // Day cutoff hour
              Text('Смена дня в: $_dayCutoffHour:00',
                  style: theme.textTheme.titleSmall),
              Slider(
                value: _dayCutoffHour.toDouble(),
                min: 0,
                max: 12,
                divisions: 12,
                label: '$_dayCutoffHour:00',
                onChanged: (v) {
                  setState(() => _dayCutoffHour = v.round());
                },
              ),
              const SizedBox(height: 12),

              // Timezone (info only)
              Text('Часовой пояс: ${widget.profile.homeTz}',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),

              const SizedBox(height: 16),

              // Save button
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
