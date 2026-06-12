### Hexlet tests and linter status:
[![Actions Status](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-318/actions)

# DevOps Engineer — Ansible Deployment

**Production:** [https://task.devops-campus.ru](https://task.devops-campus.ru)

Ansible-плейбуки для развёртывания [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy) на серверах Yandex Cloud.

В этом репозитории — **только инфраструктура и деплой**. Код приложения, `Dockerfile` и CI — в [форке приложения](https://github.com/EvgeniyMsk/project-devops-deploy).

## Репозитории

| Репозиторий | Содержимое |
|-------------|------------|
| [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy) | Java + React, Docker-образ, GitHub Actions |
| **devops-engineer-from-scratch-project-318** (этот) | Ansible, Nginx, Certbot, Node Exporter, Prometheus, деплой |

## Архитектура

```text
Internet
   │
   ▼
Nginx (:80 / :443)                         task.devops-campus.ru
   │  static: /var/www/bulletins
   │  proxy app: 127.0.0.1:8080
   ▼
application (Docker)                       Spring Boot, prod profile
   │  HTTP:        127.0.0.1:8080
   │  management:  127.0.0.1:9091 → container :9090
   │  logs: /var/log/bulletins
   ▼
database (postgres:14)                     PostgreSQL
   │  data: /var/lib/postgresql/bulletins
   ▼
Yandex Object Storage                      изображения объявлений (S3)

Nginx (:9090 HTTPS)                        мониторинг (отдельный server block)
   ├── /metrics                 → Node Exporter 127.0.0.1:9100
   ├── /actuator/prometheus     → Spring Boot 127.0.0.1:9091
   └── /actuator/health         → Spring Boot 127.0.0.1:9091

Prometheus (138.16.187.61, Docker)
   └── scrape https://task.devops-campus.ru:9090
         ├── /metrics
         └── /actuator/prometheus
```

| Компонент | Значение |
|-----------|----------|
| Web-сервер | `138.16.178.207` — приложение, Nginx, Node Exporter |
| Monitoring-сервер | `138.16.187.61` — Prometheus |
| Домен | `task.devops-campus.ru` |
| Docker-образ | `cr.yandex/crpd2isbgl7k3puo75s1/project-devops-deploy` |
| Тег по умолчанию | `latest` |
| PostgreSQL | `postgres:14` |
| S3 bucket | `hexlet-bucket` (`ru-central1`) |
| Registry | `cr.yandex` (логин: `oauth`) |

Образ собирается и публикуется CI в репозитории приложения. **Registry ID в Ansible должен совпадать с CI** (`ansible/group_vars/web_servers.yml` → `docker_image`).

### Порты web-сервера

| Порт | Доступ | Назначение |
|------|--------|------------|
| 80, 443 | публично | HTTP/HTTPS приложение |
| 9090 | monitoring + VPN (UFW) | HTTPS метрики и Actuator через Nginx |
| 8080 | `127.0.0.1` | Spring Boot HTTP |
| 9091 | `127.0.0.1` | Spring Boot management (upstream для Nginx) |
| 9100 | `127.0.0.1` | Node Exporter |

> Nginx слушает `:9090`, приложение — `:9091`. Оба порта не могут быть заняты одним процессом на `127.0.0.1:9090`.

## Структура

| Файл / каталог | Назначение |
|----------------|------------|
| `ansible/playbooks/playbook.yml` | Деплой приложения (web-сервер) |
| `ansible/playbooks/playbook-metrics.yml` | Prometheus (monitoring-сервер) |
| `Makefile` | `make galaxy`, `make setup`, `make deploy`, `make metrics` |
| `requirements.yml` | Роли Galaxy: docker, nginx, certbot |
| `ansible/inventories/inventory.ini` | Web и monitoring хосты |
| `ansible/group_vars/web_servers.yml` | Домен, образ, S3, Nginx, мониторинг |
| `ansible/group_vars/monitoring.yml` | Prometheus, scrape targets, firewall monitoring-ВМ |
| `ansible/roles/bulletins/` | Деплой, Nginx, Certbot, UFW |
| `ansible/roles/node_exporter/` | Node Exporter (системные метрики) |
| `ansible/roles/prometheus/` | Prometheus в Docker |
| `assets/monitoring/` | Документация обязательных метрик |

### Inventory

Имена хостов в группах **должны быть уникальными** — иначе Ansible объединит их в один хост и возьмёт последний `ansible_host`:

```ini
[web_servers]
web ansible_host=138.16.178.207 ansible_user=root

[monitoring]
metrics ansible_host=138.16.187.61 ansible_user=root
```

## Требования

**Control node** (ваш компьютер):

- Python 3.12+, Ansible
- `make galaxy` — установка ролей и коллекций из `requirements.yml`
- SSH-доступ к серверам
- Переменные окружения с секретами (см. ниже)

**Web-сервер** (Ubuntu 22.04+):

- DNS A-запись `task.devops-campus.ru` → `138.16.178.207`
- Каталоги: `/var/lib/postgresql/bulletins`, `/var/log/bulletins`, `/var/www/bulletins`, `/var/www/letsencrypt`

**Monitoring-сервер** (Ubuntu 22.04+, группа `monitoring`):

- Docker для контейнера Prometheus
- UFW: открыты только **22** (SSH) и **9090** (UI Prometheus)
- Docker-сеть `monitoring` — изоляция Prometheus (Grafana/Alertmanager подключатся позже)
- Volume конфигов: `/opt/prometheus/config` (включая `rules/alerts.yml`)
- Volume данных: `/var/lib/prometheus`
- Доступ к метрикам web-сервера по `https://task.devops-campus.ru:9090`

## Секреты

Не храните пароли в репозитории. Передавайте через переменные окружения:

| Переменная окружения | Ansible-переменная | Назначение |
|---------------------|-------------------|------------|
| `SPRING_DATASOURCE_USERNAME` | `spring_datasource_username` | PostgreSQL user |
| `SPRING_DATASOURCE_PASSWORD` | `spring_datasource_password` | PostgreSQL password |
| `STORAGE_S3_ACCESSKEY` | `storage_s3_accesskey` | Yandex Object Storage |
| `STORAGE_S3_SECRETKEY` | `storage_s3_secretkey` | Yandex Object Storage |
| `DOCKER_OAUTH_TOKEN` | `docker_oauth_token` | OAuth для `docker login` в YCR |
| `ANSIBLE_PASSWORD` | `ansible_password` | SSH-пароль (опционально) |

`DOCKER_OAUTH_TOKEN` должен иметь доступ к registry `crpd2isbgl7k3puo75s1` — тому же, куда CI пушит образ.

## Команды

```bash
# Установить Ansible-роли и коллекции
make galaxy

# Экспорт секретов (пример)
export SPRING_DATASOURCE_USERNAME=postgres
export SPRING_DATASOURCE_PASSWORD=...
export STORAGE_S3_ACCESSKEY=...
export STORAGE_S3_SECRETKEY=...
export DOCKER_OAUTH_TOKEN=...

# Первичная настройка web-сервера (Docker, UFW, Nginx, Certbot, БД, приложение)
make setup

# Обновление приложения
make deploy

# Откат на конкретный коммит (git SHA из CI)
make deploy ANSIBLE_DOCKER_TAG=<git-sha>

# Развёртывание Prometheus на monitoring-сервере
make metrics
```

`make deploy` запускает теги `deploy,certbot,nginx`. Порядок задач в роли `bulletins`: **deploy → nginx → certbot** (сначала контейнеры, затем Nginx).

`make metrics` разворачивает Prometheus на ВМ `138.16.187.61`: UFW, Docker-сеть `monitoring`, контейнер с отдельными volume для конфигов и данных.

## Процесс деплоя

При `make deploy` Ansible:

1. Логинится в Yandex Container Registry (`docker_oauth_token`).
2. Пересоздаёт контейнеры `database` и `application` (management на `127.0.0.1:9091`).
3. Запускает Nginx с HTTPS на `:9090` для мониторинга.
4. Обновляет Certbot и конфигурацию Nginx.
5. Извлекает frontend static из JAR в `/var/www/bulletins`.

Тег образа: `docker_tag` в `web_servers.yml` (по умолчанию `latest`) или `ANSIBLE_DOCKER_TAG` при вызове `make deploy`.

## Мониторинг

### Источники метрик

Все метрики снаружи доступны **только через HTTPS :9090**:

| Endpoint | Источник | Метрики |
|----------|----------|---------|
| `https://task.devops-campus.ru:9090/metrics` | Node Exporter | CPU, память, диски, сеть, процессы, systemd |
| `https://task.devops-campus.ru:9090/actuator/prometheus` | Spring Boot Actuator | JVM, HTTP, пул соединений БД |
| `https://task.devops-campus.ru:9090/actuator/health` | Spring Boot Actuator | Healthcheck |

Node Exporter слушает `127.0.0.1:9100` — напрямую снаружи недоступен. Nginx проксирует `/metrics` на него.

Запросы к monitoring endpoints логируются в JSON:

- access: `/var/log/nginx/monitoring-access.json` — JSON (`monitoring_json`)
- error: `/var/log/nginx/monitoring-error.json` — nginx error log (уровень `warn`)

Подробнее: [`assets/monitoring/required-metrics.md`](assets/monitoring/required-metrics.md).

### Prometheus

**URL для проверяющего:** [http://138.16.187.61:9090/graph](http://138.16.187.61:9090/graph)

| Ресурс | Адрес |
|--------|-------|
| UI / Graph | http://138.16.187.61:9090/graph |
| Targets | http://138.16.187.61:9090/targets |
| Alerts | http://138.16.187.61:9090/alerts |

Конфигурация и alert rules генерируются из Ansible vars (`ansible/group_vars/monitoring.yml` → `prometheus_scrape_jobs`). Шаблоны:

- `ansible/roles/prometheus/templates/prometheus.yml.j2` — scrape configs
- `ansible/roles/prometheus/templates/alerts.yml.j2` — alert rules (`InstanceDown`, `HighCpuLoad`)

Пример vars (новые таргеты добавляются в список без ручного редактирования конфига):

```yaml
prometheus_scrape_host: "task.devops-campus.ru:9090"

prometheus_scrape_jobs:
  - job_name: node
    metrics_path: /metrics
    scheme: https
    targets:
      - "{{ prometheus_scrape_host }}"
  - job_name: bulletins-app
    metrics_path: /actuator/prometheus
    scheme: https
    targets:
      - "{{ prometheus_scrape_host }}"
```

#### Проверка `up == 1`

1. Откройте [http://138.16.187.61:9090/targets](http://138.16.187.61:9090/targets).
2. Убедитесь, что оба таргета в состоянии **UP**:
   - `node` → `https://task.devops-campus.ru:9090/metrics`
   - `bulletins-app` → `https://task.devops-campus.ru:9090/actuator/prometheus`

Через PromQL на странице `/graph`:

```promql
up
```

Ожидаемый результат: `up{job="node"} == 1` и `up{job="bulletins-app"} == 1`.

Через API:

```bash
curl -s 'http://138.16.187.61:9090/api/v1/query?query=up' | python3 -m json.tool
```

### Обязательные метрики

| Категория | Примеры метрик | Источник |
|-----------|----------------|----------|
| CPU load | `node_load1`, `node_cpu_seconds_total` | Node Exporter |
| Память | `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes` | Node Exporter |
| Диски | `node_filesystem_avail_bytes`, `node_disk_read_bytes_total` | Node Exporter |
| Сеть | `node_network_receive_bytes_total`, `node_netstat_Tcp_CurrEstab` | Node Exporter |
| Процессы | `node_procs_running`, `node_procs_blocked` | Node Exporter |
| Сервисы | `node_systemd_unit_state` | Node Exporter |
| Приложение | `process_uptime_seconds`, `jvm_memory_used_bytes` | Actuator |
| HTTP | `http_server_requests_seconds_count` | Actuator |

## Проверка production

```bash
# Web-сервер
docker ps
docker logs application --tail 30
curl -s http://127.0.0.1:8080/api/bulletins
curl -I https://task.devops-campus.ru
certbot certificates

# Мониторинг (HTTPS :9090)
curl -s https://task.devops-campus.ru:9090/metrics | grep -E '^node_load1|^node_memory_MemAvailable'
curl -s https://task.devops-campus.ru:9090/actuator/prometheus | grep -E '^process_uptime_seconds|^http_server_requests'
curl -s https://task.devops-campus.ru:9090/actuator/health
tail -f /var/log/nginx/monitoring-access.json
systemctl status node_exporter nginx

# Monitoring-сервер — Prometheus
curl -s http://138.16.187.61:9090/api/v1/targets | python3 -m json.tool
curl -s 'http://138.16.187.61:9090/api/v1/query?query=up' | python3 -m json.tool
docker ps | grep prometheus
ufw status
```

## Типичные проблемы

| Ошибка | Решение |
|--------|---------|
| `Registry ... not found` | Проверьте `docker_image` в `web_servers.yml` — должен совпадать с CI (`crpd2isbgl7k3puo75s1`) |
| `pull is of type str ... always` | Обновите коллекции: `make galaxy` |
| Образ не найден | Убедитесь, что CI job `docker` в [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy/actions) прошёл успешно |
| 401 при pull | Проверьте `DOCKER_OAUTH_TOKEN` |
| Certbot 404 на ACME challenge | Проверьте, что DNS указывает на web-сервер; имена хостов в inventory уникальны; Nginx отдаёт `/.well-known/acme-challenge/` |
| `bind() to 0.0.0.0:9090 failed` | Контейнер `application` занимает порт — выполните `make deploy` (app → `:9091`, nginx → `:9090`) |
| `127.0.0.1:9090: address already in use` | Nginx уже слушает `:9090` — management-порт приложения должен быть `:9091` |
| Prometheus target DOWN | Проверьте UFW на web-сервере (порт 9090 для monitoring-сервера) и доступность `https://task.devops-campus.ru:9090/metrics` |

## Откат

CI публикует тег `<git-sha>` для каждого коммита в `main`:

```bash
make deploy ANSIBLE_DOCKER_TAG=f4bd182c279d1929d623dd4ed669345a5a59da3b
```

SHA смотрите в [Actions](https://github.com/EvgeniyMsk/project-devops-deploy/actions) или в логах job `docker`.
