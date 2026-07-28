import 'package:flutter/material.dart';
import '../models/announcement.dart';

/// Banner widget to display a single developer announcement
class AnnouncementBanner extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback onClose;

  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.blue[700]! : Colors.blue[200]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: isDark ? Colors.blue[300] : Colors.blue[700],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        announcement.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.blue[100] : Colors.blue[900],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        announcement.message,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.grey[300] : Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  onPressed: onClose,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
