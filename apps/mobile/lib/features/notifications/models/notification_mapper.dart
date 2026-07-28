import 'notification.dart';
import '../../../core/models/recurrence.dart';

Recurrence _recurrenceFrom(String? s) {
  switch ((s ?? 'none').toLowerCase()) {
    case 'daily':
      return Recurrence.daily;
    case 'weekly':
      return Recurrence.weekly;
    default:
      return Recurrence.none;
  }
}

DateTime? _dt(String? iso) => iso == null ? null : DateTime.parse(iso);

/// Конверт JSON FastAPI → UI-модель Notification
Notification notificationFromApiJson(Map<String, dynamic> j) {
  return Notification(
    id: j['id'] as String,
    title: j['title'] as String,
    time: _dt(j['time'] as String?) ?? DateTime.now(),
    recurrence: _recurrenceFrom(j['recurrence'] as String?),
    sent: false, // По умолчанию не отправлено (это локальное поле)
    createdAt: _dt(j['created_at'] as String?) ?? DateTime.now(),
    updatedAt: _dt(j['updated_at'] as String?) ?? DateTime.now(),
  );
}

