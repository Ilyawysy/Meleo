import 'package:flutter/material.dart';
import '../data/chat_db.dart';
import '../data/chat_sync_service.dart';

class ChatThreadSelector extends StatelessWidget {
  final String? currentThreadId;
  final ValueChanged<String?> onThreadSelected;
  final VoidCallback onNewThread;
  final ValueChanged<String>? onThreadDeleted;

  const ChatThreadSelector({
    super.key,
    required this.currentThreadId,
    required this.onThreadSelected,
    required this.onNewThread,
    this.onThreadDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Чаты',
      icon: const Icon(Icons.chat_bubble_outline),
      onPressed: () => showThreadList(context),
    );
  }

  Future<void> showThreadList(BuildContext context) async {
    final db = ChatDb();
    final threads = await db.listThreads(limit: 50);

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Чаты',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    Navigator.pop(context);
                    onNewThread();
                  },
                  tooltip: 'Новый чат',
                ),
              ],
            ),
            const Divider(),
            if (threads.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text('Чатов пока нет. Создайте новый!'),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: threads.length,
                  itemBuilder: (context, index) {
                    final thread = threads[index];
                    final isSelected = thread.id == currentThreadId;
                    return Dismissible(
                      key: Key(thread.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: Colors.red,
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                        ),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Удалить чат'),
                            content: Text('Удалить «${thread.title}»?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false),
                                child: const Text('Отмена'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true),
                                child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        ) ?? false;
                      },
                      onDismissed: (direction) async {
                        try {
                          await db.deleteThread(thread.id);
                          ChatSyncService.instance.scheduleSync();
                          if (onThreadDeleted != null) {
                            onThreadDeleted!(thread.id);
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Чат удалён')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Не удалось удалить чат: $e')),
                            );
                          }
                        }
                      },
                      child: ListTile(
                        leading: Icon(
                          Icons.chat_bubble,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          thread.title,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(
                          _formatDate(thread.updatedAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () {
                          Navigator.pop(context);
                          onThreadSelected(thread.id);
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Сегодня';
    } else if (difference.inDays == 1) {
      return 'Вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

