// lib/features/notifications/ui/notification_editor_screen.dart
import 'package:flutter/material.dart';
import '../models/notification.dart' as notification_model;
import '../../../core/models/recurrence.dart';

class NotificationEditorScreen extends StatefulWidget {
  final notification_model.Notification? initial;
  const NotificationEditorScreen({super.key, this.initial});

  @override
  State<NotificationEditorScreen> createState() => _NotificationEditorScreenState();
}

class _NotificationEditorScreenState extends State<NotificationEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _title;
  DateTime? _date;
  TimeOfDay? _time;
  Recurrence _recurrence = Recurrence.none;

  @override
  void initState() {
    super.initState();
    final n = widget.initial;
    _title = TextEditingController(text: n?.title ?? '');

    if (n != null) {
      _date = DateTime(n.time.year, n.time.month, n.time.day);
      _time = TimeOfDay(hour: n.time.hour, minute: n.time.minute);
      _recurrence = n.recurrence;
    } else {
      // Defaults for new notification: today, next hour
      final now = DateTime.now();
      final nextHour = now.minute == 0 ? now.hour : now.hour + 1;
      _date = DateTime(now.year, now.month, now.day);
      _time = TimeOfDay(hour: nextHour % 24, minute: 0);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: _date ?? now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );
    if (picked != null) setState(() => _time = picked);
  }

  DateTime? _combineDateTime(DateTime? date, TimeOfDay? time) {
    if (date == null) return null;
    if (time == null) return DateTime(date.year, date.month, date.day);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final time = _combineDateTime(_date, _time);
    if (time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date and time')),
      );
      return;
    }

    final base = widget.initial ??
        notification_model.Notification.newNotification(_title.text.trim(), time, recurrence: _recurrence);

    final updated = base.copyWith(
      title: _title.text.trim(),
      time: time,
      recurrence: _recurrence,
      updatedAt: DateTime.now(),
    );

    Navigator.of(context).pop(updated);
  }

  void _delete() {
    if (widget.initial == null) return;
    Navigator.of(context).pop({'action': 'delete', 'notification': widget.initial});
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Notification' : 'New Notification'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                hintText: 'Notification title',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
              autofocus: !isEdit,
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('Date'),
              subtitle: Text(
                _date == null
                    ? 'Select date'
                    : MaterialLocalizations.of(context).formatShortMonthDay(_date!),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Time'),
              subtitle: Text(
                _time == null
                    ? 'Select time'
                    : MaterialLocalizations.of(context).formatTimeOfDay(
                        _time!,
                        alwaysUse24HourFormat: false,
                      ),
              ),
              trailing: const Icon(Icons.access_time),
              onTap: _pickTime,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Recurrence>(
              initialValue: _recurrence,
              items: Recurrence.values
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text(switch (r) {
                        Recurrence.none => 'No recurrence',
                        Recurrence.daily => 'Repeat: Daily',
                        Recurrence.weekly => 'Repeat: Weekly',
                      }),
                    ),
                  )
                  .toList(),
              onChanged: (r) => setState(() => _recurrence = r ?? _recurrence),
              decoration: const InputDecoration(
                labelText: 'Recurrence',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(isEdit ? 'Save changes' : 'Save'),
          ),
        ),
      ),
    );
  }
}
