import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'search_constants.dart';
import 'search_normalizer.dart';

/// DAO для управления индексом поиска (search_docs и search_trigrams)
///
/// Критично: Все методы записи принимают DatabaseExecutor executor как параметр,
/// чтобы работать в той же транзакции, что и основная операция.
class SearchIndexDao {
  /// Индексировать задачу
  ///
  /// [row] должен содержать полные данные задачи: id, title, description, updated_at
  Future<void> upsertTaskRow(
    Map<String, Object?> row,
    DatabaseExecutor executor,
  ) async {
    final docId = row['id'] as String;
    final title = (row['title'] as String?) ?? '';
    final body = (row['description'] as String?) ?? '';
    final updatedAt =
        (row['updated_at'] as String?) ?? DateTime.now().toIso8601String();

    await _upsertDoc(
      SearchConstants.docTypeTask,
      docId,
      title,
      body,
      updatedAt,
      executor,
    );
  }

  /// Удалить документ из индекса
  ///
  /// Используется при soft delete (pending_delete=1) или hard delete.
  /// Явно удаляет триграммы перед удалением search_docs для гарантии консистентности
  /// (на случай, если foreign_keys не включены).
  Future<void> deleteDoc(
    int docType,
    String docId,
    DatabaseExecutor executor,
  ) async {
    // Сначала явно удалить триграммы
    await executor.delete(
      'search_trigrams',
      where: 'doc_type = ? AND doc_id = ?',
      whereArgs: [docType, docId],
    );
    // Затем удалить документ (триграммы также удалятся через ON DELETE CASCADE, если FK включены)
    await executor.delete(
      'search_docs',
      where: 'doc_type = ? AND doc_id = ?',
      whereArgs: [docType, docId],
    );
  }

  /// Перестроить весь индекс (для миграции)
  ///
  /// Принимает DatabaseExecutor executor для работы в транзакции.
  /// Транзакция должна быть создана снаружи (в DatabaseProvider).
  /// Выполняется батчами по 100 записей для tasks.
  Future<void> rebuildAll(DatabaseExecutor executor) async {
    // Очистить существующий индекс
    await executor.delete('search_trigrams');
    await executor.delete('search_docs');

    // Backfill для tasks
    await _rebuildTasks(executor);

    // Проверки после backfill (debug-only)
    // Для проверки нужен Database, а не DatabaseExecutor
    if (kDebugMode && executor is Database) {
      await _verifyBackfill(executor);
    }
  }

  /// Очистить все таблицы поиска (в транзакции)
  Future<void> clearAll(DatabaseExecutor executor) async {
    await executor.delete('search_trigrams');
    await executor.delete('search_docs');
  }

  /// Приватный метод для индексации документа
  ///
  /// 1. Нормализует title и body (body обрезает до BODY_INDEX_MAX_CHARS)
  /// 2. Вставляет/обновляет запись в search_docs
  /// 3. Удаляет старые триграммы документа
  /// 4. Генерирует и вставляет новые триграммы батчами
  Future<void> _upsertDoc(
    int docType,
    String docId,
    String title,
    String body,
    String updatedAt,
    DatabaseExecutor executor,
  ) async {
    // Обрезать body до максимальной длины для индексации
    final bodyForIndex = body.length > SearchConstants.bodyIndexMaxChars
        ? body.substring(0, SearchConstants.bodyIndexMaxChars)
        : body;

    // Нормализация
    final normTitle = SearchNormalizer.normalize(title);
    final normBody = SearchNormalizer.normalize(bodyForIndex);

    // INSERT OR REPLACE в search_docs
    // Сохраняем обрезанный body для консистентности с norm_body
    await executor.insert('search_docs', {
      'doc_type': docType,
      'doc_id': docId,
      'title': title,
      'body': bodyForIndex, // Сохраняем обрезанный body
      'norm_title': normTitle,
      'norm_body': normBody,
      'updated_at': updatedAt,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Удалить старые триграммы документа
    await executor.delete(
      'search_trigrams',
      where: 'doc_type = ? AND doc_id = ?',
      whereArgs: [docType, docId],
    );

    // Генерация триграмм для title
    final titleTrigrams = SearchNormalizer.generateTrigrams(normTitle);
    if (titleTrigrams.isNotEmpty) {
      await _insertTrigramsBatch(
        executor,
        docType,
        docId,
        titleTrigrams,
        SearchConstants.fieldTitle,
      );
    }

    // Генерация триграмм для body
    final bodyTrigrams = SearchNormalizer.generateTrigrams(normBody);
    if (bodyTrigrams.isNotEmpty) {
      await _insertTrigramsBatch(
        executor,
        docType,
        docId,
        bodyTrigrams,
        SearchConstants.fieldBody,
      );
    }
  }

  /// Вставка триграмм батчами (по 100)
  ///
  /// Использует INSERT OR IGNORE для избежания ошибок при дубликатах
  /// (хотя дубликатов быть не должно благодаря Set для уникальности).
  Future<void> _insertTrigramsBatch(
    DatabaseExecutor executor,
    int docType,
    String docId,
    Set<String> trigrams,
    int field,
  ) async {
    const batchSize = 100;
    final trigramList = trigrams.toList();

    for (int i = 0; i < trigramList.length; i += batchSize) {
      final batch = trigramList.skip(i).take(batchSize).toList();

      // Используем raw SQL с INSERT OR IGNORE для батча
      final placeholders = batch.map((_) => '(?, ?, ?, ?)').join(', ');
      final values = <Object?>[];
      for (final trigram in batch) {
        values.addAll([docType, docId, trigram, field]);
      }

      await executor.rawInsert(
        'INSERT OR IGNORE INTO search_trigrams (doc_type, doc_id, trigram, field) VALUES $placeholders',
        values,
      );
    }
  }

  /// Backfill для tasks
  ///
  /// Работает через переданный executor (без создания транзакций внутри).
  /// Использует ORDER BY для гарантии порядка и избежания пропусков/дублей.
  Future<void> _rebuildTasks(DatabaseExecutor executor) async {
    const batchSize = 100;
    int offset = 0;

    while (true) {
      final rows = await executor.query(
        'tasks',
        where: 'pending_delete = 0',
        orderBy: 'id ASC', // Гарантия порядка для избежания пропусков/дублей
        limit: batchSize,
        offset: offset,
      );

      if (rows.isEmpty) break;

      // Обрабатываем батч через переданный executor (без создания транзакции)
      for (final row in rows) {
        await upsertTaskRow(row, executor);
      }

      offset += batchSize;
      if (rows.length < batchSize) break;
    }
  }

  /// Проверка консистентности после backfill (debug-only)
  Future<void> _verifyBackfill(Database db) async {
    // Проверка COUNT инвариантов
    final tasksCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM tasks WHERE pending_delete = 0',
          ),
        ) ??
        0;

    final docsTaskCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM search_docs WHERE doc_type = ?',
            [SearchConstants.docTypeTask],
          ),
        ) ??
        0;

    if (tasksCount != docsTaskCount) {
      debugPrint(
        '⚠️ [SearchIndexDao] Backfill verification failed: '
        'tasks count ($tasksCount) != search_docs tasks count ($docsTaskCount)',
      );
    } else {
      debugPrint(
        '✅ [SearchIndexDao] Backfill verification passed: '
        'tasks=$tasksCount',
      );
    }
  }
}
