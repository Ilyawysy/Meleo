import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../models/chat_widget.dart';

class ChatWidgetCard extends StatelessWidget {
  final ChatWidget widgetData;
  final void Function(String entityType, String entityId)? onOpenEntity;

  const ChatWidgetCard({
    super.key,
    required this.widgetData,
    this.onOpenEntity,
  });

  @override
  Widget build(BuildContext context) {
    switch (widgetData.type) {
      case 'entity':
        return _buildEntityCard();
      case 'list':
        return _buildListCard();
      case 'summary':
        return _buildSummaryCard();
      default:
        return _buildUnknownCard();
    }
  }

  Widget _buildEntityCard() {
    final entity = (widgetData.data['entity'] as Map?) ?? widgetData.data;
    final entityType = entity['entity_type']?.toString() ?? '';
    final entityId = entity['entity_id']?.toString() ?? '';
    final title = entity['title']?.toString() ?? '';
    final snippet = entity['snippet']?.toString() ?? '';

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? 'Без названия' : title,
                  style: AppTypography.heading15(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (entityType.isNotEmpty &&
                  entityId.isNotEmpty &&
                  onOpenEntity != null)
                GestureDetector(
                  onTap: () => onOpenEntity!(entityType, entityId),
                  child: Text(
                    'Открыть',
                    style: AppTypography.body13(color: AppColors.primaryBlue),
                  ),
                ),
            ],
          ),
          if (snippet.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              snippet,
              style: AppTypography.body13(color: AppColors.textMedium),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListCard() {
    final items = (widgetData.data['items'] as List?) ?? [];
    final total = widgetData.data['total']?.toString();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final raw in items)
            if (raw is Map)
              _entityRow(raw.cast<String, dynamic>()),
          if (total != null && total.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Total: $total',
                style: AppTypography.caption12(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final stats = widgetData.data['stats'] as Map?;
    final groups = (widgetData.data['groups'] as List?) ?? [];

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (stats != null) _statsBlock(stats),
          for (final raw in groups)
            if (raw is Map)
              _groupBlock(raw.cast<String, dynamic>()),
        ],
      ),
    );
  }

  Widget _statsBlock(Map stats) {
    final taskStats = stats['task'] as Map? ?? {};

    String counts(Map data) {
      final create = data['create'] ?? 0;
      final update = data['update'] ?? 0;
      final delete = data['delete'] ?? 0;
      final get = data['get'] ?? 0;
      return 'created: $create, updated: $update, deleted: $delete, viewed: $get';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Tasks: ${counts(taskStats)}',
        style: AppTypography.body13(color: AppColors.textMedium),
      ),
    );
  }

  Widget _groupBlock(Map<String, dynamic> group) {
    final action = group['action']?.toString() ?? '';
    final items = (group['items'] as List?) ?? [];
    final label = _actionLabel(action);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            '$label tasks',
            style: AppTypography.body14(fontWeight: FontWeight.w600),
          ),
        ),
        for (final raw in items)
          if (raw is Map)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _entityRow(raw.cast<String, dynamic>()),
            ),
      ],
    );
  }

  Widget _entityRow(Map<String, dynamic> entity) {
    final entityType = entity['entity_type']?.toString() ?? '';
    final entityId = entity['entity_id']?.toString() ?? '';
    final title = entity['title']?.toString() ?? '';
    final snippet = entity['snippet']?.toString() ?? '';

    return GestureDetector(
      onTap: (entityType.isNotEmpty &&
              entityId.isNotEmpty &&
              onOpenEntity != null)
          ? () => onOpenEntity!(entityType, entityId)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.isEmpty ? 'Без названия' : title,
              style: AppTypography.body14(fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (snippet.isNotEmpty)
              Text(
                snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption12(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownCard() {
    return _card(
      child: Text(
        'Неизвестный тип виджета',
        style: AppTypography.body13(color: AppColors.textLight),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'create':
        return 'Создано';
      case 'update':
        return 'Обновлено';
      case 'delete':
        return 'Удалено';
      case 'get':
        return 'Получено';
      default:
        return 'Действие';
    }
  }
}
