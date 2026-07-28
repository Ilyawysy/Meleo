# Оповещения Grafana

Каталог предназначен для provisioning-конфигурации Grafana Alerting.
Datasources Prometheus и Loki создаются соседними файлами в
`../datasources/`, а dashboards — через `../dashboards/`.

В текущем showcase alert rules и contact points не содержат production
получателей. Telegram tokens, email credentials и другие значения доставки
нельзя хранить в Git.

## Источники сигналов

- **Prometheus** — HTTP-метрики API и host metrics от Node Exporter.
- **Loki** — JSON-логи API, доставляемые Promtail.

Backend использует structlog и добавляет поля `event`, `level`, `service`,
`request_id` и тип ошибки. Promtail сохраняет `service` и `source` как Loki
labels; `level`, `event` и остальные поля остаются внутри JSON log line. Для
них в LogQL сначала применяется parser `| json`, а затем фильтр по извлечённым
полям.

## Примеры условий

### Использование диска

```promql
(1 - (
  node_filesystem_avail_bytes{mountpoint="/"}
  /
  node_filesystem_size_bytes{mountpoint="/"}
)) * 100
```

Практический порог для прототипа: значение выше `90` в течение `5m`.

### Загрузка CPU

```promql
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### Неожиданные ошибки API

```logql
sum(count_over_time(
  {service="api"} | json | level="error" | event="unexpected_error" [5m]
))
```

Конкретные thresholds зависят от окружения и ожидаемой нагрузки; showcase не
объявляет их production SLO.

## Локальная проверка

После изменения provisioning-файлов проверьте YAML и перезапустите Grafana в
локальном dev-окружении:

```bash
cd infra/docker
docker compose restart grafana
```

Если изменился Promtail pipeline, новые значения labels `service` и `source`
появятся только для логов, полученных после перезапуска Promtail.
