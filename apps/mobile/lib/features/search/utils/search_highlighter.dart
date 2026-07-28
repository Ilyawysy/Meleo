import 'package:flutter/material.dart';

/// Утилита для генерации подсветки совпадений в результатах поиска
class SearchHighlighter {
  // Параметры для генерации snippet из body
  static const int maxMatchesPerToken = 20;
  static const int windowLen = 100;
  static const int leftContext = 35;

  /// Подсветка title - все совпадения токенов
  ///
  /// Возвращает список TextSpan с подсвеченными совпадениями токенов.
  static List<TextSpan> highlightTitle(String title, List<String> tokens) {
    if (tokens.isEmpty || title.isEmpty) {
      return [TextSpan(text: title)];
    }

    // Находим все позиции совпадений токенов
    final matches = <_Match>[];
    final normalizedTitle = title.toLowerCase();

    for (final token in tokens) {
      final normalizedToken = token.toLowerCase();
      int startIndex = 0;
      while (true) {
        final index = normalizedTitle.indexOf(normalizedToken, startIndex);
        if (index == -1) break;
        matches.add(_Match(index: index, length: token.length, token: token));
        startIndex = index + 1;
      }
    }

    // Сортируем совпадения по позиции
    matches.sort((a, b) => a.index.compareTo(b.index));

    // Объединяем перекрывающиеся совпадения
    final mergedMatches = <_Match>[];
    for (final match in matches) {
      if (mergedMatches.isEmpty) {
        mergedMatches.add(match);
      } else {
        final last = mergedMatches.last;
        if (match.index <= last.index + last.length) {
          // Перекрываются - расширяем последнее совпадение
          final newEnd = match.index + match.length;
          final oldEnd = last.index + last.length;
          mergedMatches[mergedMatches.length - 1] = _Match(
            index: last.index,
            length: newEnd > oldEnd ? newEnd - last.index : last.length,
            token: last.token,
          );
        } else {
          mergedMatches.add(match);
        }
      }
    }

    // Генерируем TextSpan'ы
    final spans = <TextSpan>[];
    int currentIndex = 0;

    for (final match in mergedMatches) {
      // Текст до совпадения
      if (match.index > currentIndex) {
        spans.add(TextSpan(text: title.substring(currentIndex, match.index)));
      }

      // Подсвеченный текст
      final highlightedText = title.substring(
        match.index,
        match.index + match.length,
      );
      spans.add(
        TextSpan(
          text: highlightedText,
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      currentIndex = match.index + match.length;
    }

    // Текст после последнего совпадения
    if (currentIndex < title.length) {
      spans.add(TextSpan(text: title.substring(currentIndex)));
    }

    return spans.isEmpty ? [TextSpan(text: title)] : spans;
  }

  /// Подсветка body - выбор лучшего snippet с подсветкой
  ///
  /// Алгоритм:
  /// 1. Найти все позиции вхождений токенов (до maxMatchesPerToken каждого)
  /// 2. Для каждого вхождения создать окно-кандидат
  /// 3. Оценить каждое окно по скору
  /// 4. Выбрать окно с максимальным скором
  /// 5. Сформировать snippet с подсветкой и "..." если нужно
  static List<TextSpan> highlightBody(
    String body,
    List<String> tokens, {
    int maxMatches = maxMatchesPerToken,
    int windowLength = windowLen,
    int leftContextSize = leftContext,
  }) {
    if (tokens.isEmpty || body.isEmpty) {
      return [TextSpan(text: body)];
    }

    // 1. Найти все позиции вхождений токенов
    final tokenMatches = <String, List<_Match>>{};
    final normalizedBody = body.toLowerCase();

    for (final token in tokens) {
      final normalizedToken = token.toLowerCase();
      final matches = <_Match>[];
      int startIndex = 0;
      int matchCount = 0;

      while (matchCount < maxMatches) {
        final index = normalizedBody.indexOf(normalizedToken, startIndex);
        if (index == -1) break;
        matches.add(_Match(index: index, length: token.length, token: token));
        startIndex = index + 1;
        matchCount++;
      }

      if (matches.isNotEmpty) {
        tokenMatches[token] = matches;
      }
    }

    if (tokenMatches.isEmpty) {
      return [TextSpan(text: body)];
    }

    // 2. Создать окна-кандидаты для каждого вхождения
    final windows = <_Window>[];

    for (final entry in tokenMatches.entries) {
      for (final match in entry.value) {
        final start = (match.index - leftContextSize).clamp(0, body.length);
        final end = (start + windowLength).clamp(0, body.length);

        // Найти все токены, которые попадают в это окно
        final tokensInWindow = <String>{};
        for (final tokenEntry in tokenMatches.entries) {
          for (final tokenMatch in tokenEntry.value) {
            if (tokenMatch.index >= start && tokenMatch.index < end) {
              tokensInWindow.add(tokenEntry.key);
            }
          }
        }

        // Вычислить позицию совпадения относительно начала окна
        final matchOffset = match.index - start;

        windows.add(
          _Window(
            start: start,
            end: end,
            matchStart: match.index,
            tokensInWindow: tokensInWindow,
            matchOffset: matchOffset,
          ),
        );
      }
    }

    if (windows.isEmpty) {
      return [TextSpan(text: body)];
    }

    // 3. Оценить каждое окно по скору
    for (final window in windows) {
      int score = 0;

      // +10 за каждое уникальное слово запроса в окне
      score += window.tokensInWindow.length * 10;

      // +5 если совпадение ближе к началу окна
      final positionBonus =
          ((windowLength - window.matchOffset) / windowLength) * 5;
      score += positionBonus.round();

      // +20 если совпадения идут подряд (для длинных токенов)
      // Проверяем, есть ли несколько токенов подряд
      final sortedMatches = <_Match>[];
      for (final entry in tokenMatches.entries) {
        for (final match in entry.value) {
          if (match.index >= window.start && match.index < window.end) {
            sortedMatches.add(match);
          }
        }
      }
      sortedMatches.sort((a, b) => a.index.compareTo(b.index));

      // Проверяем последовательные совпадения
      for (int i = 0; i < sortedMatches.length - 1; i++) {
        final current = sortedMatches[i];
        final next = sortedMatches[i + 1];
        if (next.index == current.index + current.length) {
          score += 20;
          break; // Достаточно одного случая последовательности
        }
      }

      window.score = score;
    }

    // 4. Выбрать окно с максимальным скором
    windows.sort((a, b) => b.score.compareTo(a.score));
    final bestWindow = windows.first;

    // 5. Сформировать snippet с подсветкой
    final snippet = body.substring(bestWindow.start, bestWindow.end);
    final hasLeftEllipsis = bestWindow.start > 0;
    final hasRightEllipsis = bestWindow.end < body.length;

    // Найти все совпадения токенов в snippet
    final snippetMatches = <_Match>[];
    final snippetStart = bestWindow.start;
    final normalizedSnippet = snippet.toLowerCase();

    for (final entry in tokenMatches.entries) {
      final normalizedToken = entry.key.toLowerCase();
      int startIndex = 0;
      while (true) {
        final index = normalizedSnippet.indexOf(normalizedToken, startIndex);
        if (index == -1) break;
        snippetMatches.add(
          _Match(
            index: snippetStart + index,
            length: entry.key.length,
            token: entry.key,
          ),
        );
        startIndex = index + 1;
      }
    }

    // Сортируем совпадения по позиции
    snippetMatches.sort((a, b) => a.index.compareTo(b.index));

    // Объединяем перекрывающиеся совпадения
    final mergedSnippetMatches = <_Match>[];
    for (final match in snippetMatches) {
      final relativeIndex = match.index - snippetStart;
      if (mergedSnippetMatches.isEmpty) {
        mergedSnippetMatches.add(
          _Match(
            index: relativeIndex,
            length: match.length,
            token: match.token,
          ),
        );
      } else {
        final last = mergedSnippetMatches.last;
        if (relativeIndex <= last.index + last.length) {
          // Перекрываются - расширяем последнее совпадение
          final newEnd = relativeIndex + match.length;
          final oldEnd = last.index + last.length;
          mergedSnippetMatches[mergedSnippetMatches.length - 1] = _Match(
            index: last.index,
            length: newEnd > oldEnd ? newEnd - last.index : last.length,
            token: last.token,
          );
        } else {
          mergedSnippetMatches.add(
            _Match(
              index: relativeIndex,
              length: match.length,
              token: match.token,
            ),
          );
        }
      }
    }

    // Генерируем TextSpan'ы для snippet
    final spans = <TextSpan>[];

    // Добавляем "..." слева, если нужно
    if (hasLeftEllipsis) {
      spans.add(const TextSpan(text: '...'));
    }

    int currentIndex = 0;
    for (final match in mergedSnippetMatches) {
      // Текст до совпадения
      if (match.index > currentIndex) {
        spans.add(TextSpan(text: snippet.substring(currentIndex, match.index)));
      }

      // Подсвеченный текст
      final highlightedText = snippet.substring(
        match.index,
        match.index + match.length,
      );
      spans.add(
        TextSpan(
          text: highlightedText,
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      currentIndex = match.index + match.length;
    }

    // Текст после последнего совпадения
    if (currentIndex < snippet.length) {
      spans.add(TextSpan(text: snippet.substring(currentIndex)));
    }

    // Добавляем "..." справа, если нужно
    if (hasRightEllipsis) {
      spans.add(const TextSpan(text: '...'));
    }

    return spans.isEmpty ? [TextSpan(text: snippet)] : spans;
  }
}

/// Вспомогательный класс для хранения информации о совпадении
class _Match {
  final int index;
  final int length;
  final String token;

  _Match({required this.index, required this.length, required this.token});
}

/// Вспомогательный класс для хранения информации об окне-кандидате
class _Window {
  final int start;
  final int end;
  final int matchStart;
  final Set<String> tokensInWindow;
  final int matchOffset;
  int score = 0;

  _Window({
    required this.start,
    required this.end,
    required this.matchStart,
    required this.tokensInWindow,
    required this.matchOffset,
  });
}
