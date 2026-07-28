import 'package:flutter/material.dart';
import '../models/notification.dart' as notification_model;
import '../../../core/models/recurrence.dart';

enum NotificationFilter { all, today, tomorrow }

class NotificationsTab extends StatefulWidget {
  final List<notification_model.Notification> notifications;
  final ValueChanged<notification_model.Notification> onEdit;
  final ValueChanged<notification_model.Notification> onDelete;

  const NotificationsTab({
    super.key,
    required this.notifications,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  NotificationFilter _filter = NotificationFilter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    List<notification_model.Notification> filtered = widget.notifications.where((n) {
      // Фильтруем отправленные уведомления (если они не повторяются)
      // Они уже были показаны системой и должны исчезнуть из UI
      if (n.sent && n.recurrence == Recurrence.none) {
        return false;
      }
      
      if (_query.isNotEmpty && !n.title.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      switch (_filter) {
        case NotificationFilter.today:
          if (!n.isToday) return false;
          break;
        case NotificationFilter.tomorrow:
          if (!n.isTomorrow) return false;
          break;
        case NotificationFilter.all:
          break;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => a.time.compareTo(b.time));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search notifications…',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) {
              setState(() {
                _query = value.trim();
              });
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter == NotificationFilter.all,
                onTap: () {
                  setState(() => _filter = NotificationFilter.all);
                },
              ),
              _FilterChip(
                label: 'Today',
                selected: _filter == NotificationFilter.today,
                onTap: () {
                  setState(() => _filter = NotificationFilter.today);
                },
              ),
              _FilterChip(
                label: 'Tomorrow',
                selected: _filter == NotificationFilter.tomorrow,
                onTap: () {
                  setState(() => _filter = NotificationFilter.tomorrow);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_outlined,
                          size: 56,
                          color: Theme.of(context).hintColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _query.isNotEmpty
                              ? 'No notifications found'
                              : 'No notifications',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _query.isNotEmpty
                              ? 'Try a different search query'
                              : 'Add a new notification',
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final n = filtered[i];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.notifications_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(n.title),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  MaterialLocalizations.of(context).formatTimeOfDay(
                                    TimeOfDay.fromDateTime(n.time),
                                    alwaysUse24HourFormat: false,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  MaterialLocalizations.of(context).formatShortMonthDay(n.time),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).hintColor,
                                  ),
                                ),
                              ],
                            ),
                            if (n.recurrence != Recurrence.none)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.repeat,
                                      size: 14,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      n.recurrence == Recurrence.daily ? 'Daily' : 'Weekly',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'edit') {
                              widget.onEdit(n);
                            } else if (value == 'delete') {
                              widget.onDelete(n);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline),
                                  SizedBox(width: 8),
                                  Text('Delete'),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () => widget.onEdit(n),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
