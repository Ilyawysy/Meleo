import 'package:flutter/material.dart';

/// Результат поиска
class SearchResult {
  final int docType;
  final String docId;
  final String title;
  final String? subtitle; // description для tasks
  final double score;

  // Подсвеченный текст (null если подсветка не применялась)
  final List<TextSpan>? highlightedTitle;
  final List<TextSpan>? highlightedBody;

  SearchResult({
    required this.docType,
    required this.docId,
    required this.title,
    this.subtitle,
    required this.score,
    this.highlightedTitle,
    this.highlightedBody,
  });
}
