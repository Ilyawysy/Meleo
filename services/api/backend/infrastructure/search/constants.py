"""Search constants - contract parameters for pg_trgm search"""

# Порог похожести для оператора % (устанавливается через SET LOCAL)
SIMILARITY_THRESHOLD = 0.1

# Веса для ранжирования
W_TITLE = 3.0  # Вес для совпадений в title
W_BODY = 1.0   # Вес для совпадений в body/description/text
W_TITLE_PREFIX = 0.5  # Бонус за префикс-совпадение в title в ILIKE fallback (q_norm || '%')

# Минимальная длина запроса для триграммного поиска
MIN_QUERY_LENGTH_FOR_TRIGRAM = 3

# Лимиты для поиска
CANDIDATE_LIMIT = 200  # Лимит кандидатов (100 по title + 100 по text/description для триграммного поиска)
RESULT_LIMIT = 20      # Лимит итоговых результатов
