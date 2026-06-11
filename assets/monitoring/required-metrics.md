# Обязательные метрики для Prometheus

Документ описывает метрики, которые должны собираться в production-окружении доски объявлений.

## Источники

| Источник | Endpoint | Порт | Описание |
|----------|----------|------|----------|
| Node Exporter | `http://127.0.0.1:9100/metrics` | 9100 | Системные метрики хоста |
| Spring Boot Actuator | `https://task.devops-campus.ru/actuator/prometheus` | 443 (Nginx → 9090) | Метрики JVM и HTTP приложения |
| Spring Boot Actuator | `https://task.devops-campus.ru/actuator/health` | 443 (Nginx → 9090) | Healthcheck |

## Категории обязательных метрик

### CPU load

- `node_load1`, `node_load5`, `node_load15` — средняя нагрузка за 1/5/15 минут
- `node_cpu_seconds_total` — время CPU по режимам (idle, user, system, iowait)

### Память

- `node_memory_MemTotal_bytes` — объём RAM
- `node_memory_MemAvailable_bytes` — доступная память
- `node_memory_SwapTotal_bytes`, `node_memory_SwapFree_bytes` — swap

### Диски

- `node_filesystem_size_bytes`, `node_filesystem_avail_bytes`, `node_filesystem_free_bytes` — место на ФС
- `node_filesystem_readonly` — read-only монтирования
- `node_disk_read_bytes_total`, `node_disk_written_bytes_total` — I/O дисков
- `node_disk_io_time_seconds_total` — время I/O

### Сеть

- `node_network_receive_bytes_total`, `node_network_transmit_bytes_total` — трафик по интерфейсам
- `node_network_receive_errs_total`, `node_network_transmit_errs_total` — ошибки сети
- `node_netstat_Tcp_CurrEstab` — активные TCP-соединения

### Процессы

- `node_procs_running` — запущенные процессы
- `node_procs_blocked` — заблокированные процессы
- `node_procs_total` — общее число процессов

### Системные сервисы (systemd)

- `node_systemd_unit_state` — состояние unit'ов (`nginx`, `docker`, `node_exporter`, `ssh`, `ufw`, `cron`, `rsyslog`)

### Приложение (Actuator / Micrometer)

- `process_uptime_seconds` — uptime JVM
- `jvm_memory_used_bytes`, `jvm_memory_max_bytes` — память JVM
- `jvm_gc_pause_seconds_sum`, `jvm_gc_pause_seconds_count` — GC
- `http_server_requests_seconds_count` — число HTTP-запросов
- `http_server_requests_seconds_sum` — суммарное время запросов
- `http_server_requests_seconds_max` — максимальная латентность
- `jdbc_connections_active` — активные соединения с БД (если экспортируется)
- `hikaricp_connections_active` — пул HikariCP (если экспортируется)

## Пример scrape_config для Prometheus

```yaml
scrape_configs:
  - job_name: node
    static_configs:
      - targets: ["127.0.0.1:9100"]

  - job_name: bulletins-app
    metrics_path: /actuator/prometheus
    scheme: https
    static_configs:
      - targets: ["task.devops-campus.ru"]
```

## Логи Nginx (monitoring endpoints)

Запросы к `/actuator/health` и `/actuator/prometheus` логируются отдельно от основного трафика:

| Лог | Путь | Формат |
|-----|------|--------|
| Access | `/var/log/nginx/monitoring-access.json` | JSON (`monitoring_json`) |
| Error | `/var/log/nginx/monitoring-error.json` | nginx error log (уровень `warn`) |

Ошибки upstream (502/503/504) дополнительно отражаются в JSON access-логе в поле `status`. Access-лог готов для ingestion в Loki/ELK без парсинга.
