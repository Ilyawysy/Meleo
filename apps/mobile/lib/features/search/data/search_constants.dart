/// Константы для системы поиска с триграммами
class SearchConstants {
  // Типы документов
  static const int docTypeTask = 0;

  // Поля для индексации
  static const int fieldTitle = 0;
  static const int fieldBody = 1;

  // Ограничения
  static const int bodyIndexMaxChars = 4000;

  // Веса для ранжирования
  static const int titleWeight = 3;
  static const int bodyWeight = 1;

  // Лимиты для поиска
  static const int candidateLimit = 200; // overfetch для фильтров
  static const int uiLimit = 5; // финальный результат для UI
  static const int maxTrigramsForSql = 300; // максимум триграмм в одном SQL запросе

  // UI настройки
  static const int searchDebounceMs = 200;
}
