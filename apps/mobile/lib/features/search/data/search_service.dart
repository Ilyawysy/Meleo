import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/database_provider.dart';
import '../models/search_result.dart';
import '../utils/search_highlighter.dart';
import 'search_constants.dart';
import 'search_normalizer.dart';

/// Сервис для полнотекстового поиска с триграммами
class SearchService {
  /// Выполнить поиск
  ///
  /// [query] - поисковый запрос
  /// [docType] - тип документа (null = tasks)
  /// Фильтры для tasks: [status], [trashed], [projectId]
  Future<List<SearchResult>> search(
    String query, {
    int? docType,
    // Фильтры для tasks:
    String? status,
    bool? trashed,
    String? projectId,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Нормализация запроса
    final normalizedQuery = SearchNormalizer.normalize(query);

    // 2. Пустой запрос
    if (normalizedQuery.isEmpty) {
      return [];
    }

    // 3. Токенизация
    final tokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      return [];
    }

    // 4. Обработка коротких запросов (<3 символов)
    final longTokens = tokens.where((t) => t.length >= 3).toList();
    if (longTokens.isEmpty) {
      // Fallback через LIKE по search_docs
      // Используем все токены (включая короткие <3 символов)
      return await _searchWithLike(
        tokens,
        docType: docType,
        status: status,
        trashed: trashed,
        projectId: projectId,
      );
    }

    // 5. Генерация триграмм из токенов
    // Приоритет длинным токенам: сортируем токены по длине убыванию
    // и набираем триграммы до MAX_TRIGRAMS_FOR_SQL в цикле
    final sortedTokens = List<String>.from(longTokens)
      ..sort((a, b) => b.length.compareTo(a.length));

    final limitedTrigrams = <String>[];
    for (final token in sortedTokens) {
      final tokenTrigrams = SearchNormalizer.generateTrigrams(token);
      for (final trigram in tokenTrigrams) {
        if (!limitedTrigrams.contains(trigram)) {
          limitedTrigrams.add(trigram);
          if (limitedTrigrams.length >= SearchConstants.maxTrigramsForSql) {
            break;
          }
        }
      }
      if (limitedTrigrams.length >= SearchConstants.maxTrigramsForSql) {
        break;
      }
    }

    // 6. Поиск через триграммы
    final candidates = await _searchWithTrigrams(
      limitedTrigrams,
      docType: docType,
    );

    // 7. Strict верификация: проверка всех токенов
    final strictResults = await _verifyCandidatesStrict(candidates, longTokens);

    // 8. Если strict проверка не дала результатов, применяем soft проверку
    List<Map<String, Object?>> verifiedCandidates;
    if (strictResults.isNotEmpty) {
      verifiedCandidates = strictResults;
    } else {
      verifiedCandidates = await _verifyCandidatesSoft(candidates, longTokens);
    }

    // 9. Применение фильтров к реальным записям
    final filteredResults = await _applyFilters(
      verifiedCandidates,
      status: status,
      trashed: trashed,
      projectId: projectId,
    );

    // 10. Ранжирование уже выполнено в SQL (score) и сохранено в verifiedCandidates
    // 11. Ограничение: вернуть top-5
    final results = filteredResults.take(SearchConstants.uiLimit).toList();

    // 12. Генерация подсветки для результатов
    final highlightedResults = await Future.wait(
      results.map((result) async {
        // Генерируем подсветку для title
        final highlightedTitle = SearchHighlighter.highlightTitle(
          result.title,
          longTokens,
        );

        List<TextSpan>? highlightedBody;
        if (result.subtitle != null) {
          highlightedBody = SearchHighlighter.highlightBody(
            result.subtitle!,
            longTokens,
          );
        }

        // Возвращаем новый SearchResult с подсветкой
        return SearchResult(
          docType: result.docType,
          docId: result.docId,
          title: result.title,
          subtitle: result.subtitle,
          score: result.score,
          highlightedTitle: highlightedTitle,
          highlightedBody: highlightedBody,
        );
      }),
    );

    if (kDebugMode) {
      stopwatch.stop();
      final strictCount = strictResults.length;
      final softCount = strictCount == 0 ? verifiedCandidates.length : 0;
      debugPrint(
        '🔍 [SearchService] search(query="${query.substring(0, query.length > 20 ? 20 : query.length)}...") '
        'total=${stopwatch.elapsedMilliseconds}ms, '
        'candidates=${candidates.length}, '
        'strict=$strictCount, '
        'soft=$softCount, '
        'verified=${verifiedCandidates.length}, '
        'filtered=${filteredResults.length}, '
        'results=${highlightedResults.length}',
      );
    }

    return highlightedResults;
  }

  /// Поиск через триграммы
  ///
  /// Оптимизация: строим SQL динамически для лучшего использования индекса (trigram, doc_type).
  /// Если docType == null, убираем условие doc_type из WHERE, что позволяет использовать индекс эффективнее.
  Future<List<Map<String, Object?>>> _searchWithTrigrams(
    List<String> trigrams, {
    int? docType,
  }) async {
    final db = await DatabaseProvider().getDatabase();

    if (trigrams.isEmpty) {
      return [];
    }

    // Строим SQL запрос динамически
    final placeholders = trigrams.map((_) => '?').join(', ');
    final docTypeCondition = docType != null ? 'AND doc_type = ?' : '';

    final sql =
        '''
      SELECT doc_type, doc_id, 
             SUM(CASE WHEN field = ${SearchConstants.fieldTitle} THEN ${SearchConstants.titleWeight} ELSE ${SearchConstants.bodyWeight} END) as score
      FROM search_trigrams
      WHERE trigram IN ($placeholders)
        $docTypeCondition
      GROUP BY doc_type, doc_id
      ORDER BY score DESC
      LIMIT ${SearchConstants.candidateLimit}
    ''';

    final args = <Object?>[...trigrams, if (docType != null) docType];

    final rows = await db.rawQuery(sql, args);
    return rows;
  }

  /// Fallback поиск через LIKE для коротких запросов
  ///
  /// Использует SQL LIKE для поиска по нормализованным полям.
  /// Score аддитивный: (norm_title LIKE ?)*TITLE_WEIGHT + (norm_body LIKE ?)*BODY_WEIGHT
  /// WHERE использует AND по каждому токену: для каждого токена проверяется
  /// (norm_title LIKE '%token%' OR norm_body LIKE '%token%')
  ///
  /// Порядок args строго соответствует порядку '?' в SQL:
  /// 1. Для CASE WHEN в SELECT: для каждого токена - 2 '?' (title, body)
  /// 2. Для WHERE: docType (если есть), затем для каждого токена - 2 '?' (title, body)
  Future<List<SearchResult>> _searchWithLike(
    List<String> tokens, {
    int? docType,
    String? status,
    bool? trashed,
    String? projectId,
  }) async {
    if (tokens.isEmpty) {
      return [];
    }

    // Дедупликация токенов (сохраняем порядок первого вхождения)
    final uniqueTokens = <String>[];
    final seenTokens = <String>{};
    for (final token in tokens) {
      if (!seenTokens.contains(token)) {
        uniqueTokens.add(token);
        seenTokens.add(token);
      }
    }

    // Фильтруем слишком короткие токены (1 символ) - они создают слишком много шума
    // Для токенов длиной 2 символа оставляем как есть (строгий режим)
    final filteredTokens = uniqueTokens.where((t) => t.length >= 2).toList();

    if (filteredTokens.isEmpty) {
      return [];
    }

    final db = await DatabaseProvider().getDatabase();

    // Строим SQL с аддитивным score и AND по каждому токену
    final conditions = <String>[];
    final args = <Object?>[];

    // 1. Собираем CASE WHEN для score (аддитивный)
    // Для каждого токена: (CASE WHEN norm_title LIKE ? THEN TITLE_WEIGHT ELSE 0 END) +
    //                     (CASE WHEN norm_body LIKE ? THEN BODY_WEIGHT ELSE 0 END)
    final scoreCases = <String>[];
    for (final token in filteredTokens) {
      final likePattern = '%$token%';
      // Добавляем args для CASE WHEN (в порядке появления '?' в SQL)
      args.add(likePattern); // для norm_title LIKE
      args.add(likePattern); // для norm_body LIKE

      scoreCases.add(
        '(CASE WHEN norm_title LIKE ? THEN ${SearchConstants.titleWeight} ELSE 0 END) + '
        '(CASE WHEN norm_body LIKE ? THEN ${SearchConstants.bodyWeight} ELSE 0 END)',
      );
    }

    // 2. Фильтр по типу документа (если указан)
    if (docType != null) {
      conditions.add('doc_type = ?');
      args.add(docType);
    }

    // 3. WHERE: для каждого токена проверяем (norm_title LIKE ? OR norm_body LIKE ?)
    // и соединяем через AND
    final tokenConditions = <String>[];
    for (final token in filteredTokens) {
      final likePattern = '%$token%';
      // Добавляем args для WHERE (в порядке появления '?' в SQL)
      args.add(likePattern); // для norm_title LIKE
      args.add(likePattern); // для norm_body LIKE

      tokenConditions.add('(norm_title LIKE ? OR norm_body LIKE ?)');
    }
    conditions.add(tokenConditions.join(' AND '));

    final sql =
        '''
      SELECT doc_type, doc_id, title, body,
             ${scoreCases.join(' + ')} as score
      FROM search_docs
      WHERE ${conditions.join(' AND ')}
      ORDER BY score DESC, updated_at DESC
      LIMIT ${SearchConstants.candidateLimit}
    ''';

    final rows = await db.rawQuery(sql, args);

    // Верификация и применение фильтров
    final candidates = rows
        .map(
          (row) => {
            'doc_type': row['doc_type'] as int,
            'doc_id': row['doc_id'] as String,
            'score': (row['score'] as num).toDouble(),
          },
        )
        .toList();

    return await _applyFilters(
      candidates,
      status: status,
      trashed: trashed,
      projectId: projectId,
    );
  }

  /// Load normalized text (norm_title + norm_body) for each candidate from search_docs.
  Future<Map<String, String>> _loadDocTexts(
    List<Map<String, Object?>> candidates,
  ) async {
    final db = await DatabaseProvider().getDatabase();
    final docIds = candidates.map((c) => c['doc_id'] as String).toList();
    final placeholders = docIds.map((_) => '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT doc_id, norm_title, norm_body
      FROM search_docs
      WHERE doc_id IN ($placeholders)
      ''', docIds);

    final docTextMap = <String, String>{};
    for (final row in rows) {
      final docId = row['doc_id'] as String;
      final normTitle = (row['norm_title'] as String?) ?? '';
      final normBody = (row['norm_body'] as String?) ?? '';
      docTextMap[docId] = '$normTitle $normBody';
    }
    return docTextMap;
  }

  /// Strict verification: all tokens must be present in the document.
  Future<List<Map<String, Object?>>> _verifyCandidatesStrict(
    List<Map<String, Object?>> candidates,
    List<String> tokens,
  ) async {
    if (candidates.isEmpty || tokens.isEmpty) {
      return [];
    }

    final docTextMap = await _loadDocTexts(candidates);

    final verified = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      final docId = candidate['doc_id'] as String;
      final combinedText = docTextMap[docId];
      if (combinedText == null) continue;

      final allFound = tokens.every((token) => combinedText.contains(token));
      if (allFound) {
        verified.add(candidate);
      }
    }

    return verified;
  }

  /// Soft verification: partial token matching with score penalty.
  ///
  /// Rules:
  /// - 2 tokens: min 1 match, score * 0.3
  /// - 3 tokens: min 2 matches
  /// - 4+ tokens: min N-1 matches
  Future<List<Map<String, Object?>>> _verifyCandidatesSoft(
    List<Map<String, Object?>> candidates,
    List<String> tokens,
  ) async {
    if (candidates.isEmpty || tokens.isEmpty) {
      return [];
    }

    final docTextMap = await _loadDocTexts(candidates);

    final tokenCount = tokens.length;
    int minRequiredTokens;
    double scorePenalty = 1.0;

    if (tokenCount == 2) {
      minRequiredTokens = 1;
      scorePenalty = 0.3;
    } else if (tokenCount == 3) {
      minRequiredTokens = 2;
    } else {
      minRequiredTokens = tokenCount - 1;
    }

    final verified = <Map<String, Object?>>[];
    for (final candidate in candidates) {
      final docId = candidate['doc_id'] as String;
      final combinedText = docTextMap[docId];
      if (combinedText == null) continue;

      int foundTokens = 0;
      for (final token in tokens) {
        if (combinedText.contains(token)) {
          foundTokens++;
        }
      }

      if (foundTokens >= minRequiredTokens) {
        final originalScore =
            (candidate['score'] as num?)?.toDouble() ?? 0.0;
        verified.add({
          'doc_type': candidate['doc_type'],
          'doc_id': docId,
          'score': originalScore * scorePenalty,
        });
      }
    }

    return verified;
  }

  /// Применение фильтров к реальным записям из tasks
  Future<List<SearchResult>> _applyFilters(
    List<Map<String, Object?>> candidates, {
    String? status,
    bool? trashed,
    String? projectId,
  }) async {
    if (candidates.isEmpty) {
      return [];
    }

    final db = await DatabaseProvider().getDatabase();

    // Разделяем кандидатов по типам
    final taskCandidates = candidates
        .where((c) => c['doc_type'] == SearchConstants.docTypeTask)
        .toList();

    final results = <SearchResult>[];

    // Фильтрация tasks
    if (taskCandidates.isNotEmpty) {
      // Создаём Map для быстрого поиска score по doc_id
      final scoreMap = <String, double>{};
      for (final candidate in taskCandidates) {
        final docId = candidate['doc_id'] as String;
        scoreMap[docId] = (candidate['score'] as num?)?.toDouble() ?? 0.0;
      }

      final taskIds = taskCandidates.map((c) => c['doc_id'] as String).toList();
      final placeholders = taskIds.map((_) => '?').join(', ');

      final conditions = <String>['pending_delete = 0'];
      final args = <Object?>[];

      // Фильтр trashed: если указан, добавляем условие trashed = 0/1
      // trashed == false означает показать только не удалённые (trashed = 0)
      // trashed == true означает показать только удалённые (trashed = 1)
      if (trashed != null) {
        conditions.add('trashed = ?');
        args.add(trashed ? 1 : 0);
      }
      if (status != null) {
        conditions.add('status = ?');
        args.add(status);
      }
      if (projectId != null) {
        conditions.add('project_id = ?');
        args.add(projectId);
      }

      conditions.add('id IN ($placeholders)');
      args.addAll(taskIds);

      final taskRows = await db.query(
        'tasks',
        where: conditions.join(' AND '),
        whereArgs: args,
      );

      // Создаём SearchResult для tasks (сохраняем порядок из SQL запроса)
      for (final taskRow in taskRows) {
        final taskId = taskRow['id'] as String;
        final score = scoreMap[taskId] ?? 0.0;

        results.add(
          SearchResult(
            docType: SearchConstants.docTypeTask,
            docId: taskId,
            title: (taskRow['title'] as String?) ?? '',
            subtitle: taskRow['description'] as String?,
            score: score,
          ),
        );
      }
    }

    // Сортировка по score
    results.sort((a, b) => b.score.compareTo(a.score));

    return results;
  }
}
