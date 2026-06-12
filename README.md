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

Prometheus + Grafana (138.16.187.61, Docker, сеть monitoring)
   ├── Prometheus → scrape https://task.devops-campus.ru:9090
   │     ├── /metrics          (node)
   │     ├── /nginx/metrics    (nginx stub_status)
   │     └── /actuator/prometheus (app)
   └── Grafana → dashboards, alert rules → Telegram

Promtail (138.16.178.207, systemd) → Loki (138.16.187.61:3100, Docker, UFW: только web-сервер)
   ├── docker logs (application, database) — JSON stdout
   ├── /var/log/bulletins/*.log
   └── Nginx JSON access logs
```

| Компонент | Значение |
|-----------|----------|
| **App VM** (`web_servers` / `app`) | `138.16.178.207` — приложение, Nginx, Node/nginx exporters, Promtail |
| **Monitoring VM** | `138.16.187.61` — Prometheus, Loki, Grafana |
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
| 9113 | `127.0.0.1` | nginx-prometheus-exporter |
| 8082 | `127.0.0.1` | Nginx stub_status (`/nginx_status`) |
| 9080 | `127.0.0.1` | Promtail metrics/health |

> Nginx слушает `:9090`, приложение — `:9091`. Оба порта не могут быть заняты одним процессом на `127.0.0.1:9090`.

## Структура репозитория

```text
.
├── ansible/
│   ├── ansible.cfg
│   ├── .ansible-lint
│   ├── group_vars/
│   │   ├── web_servers.yml    # app VM (переменные без секретов)
│   │   └── monitoring.yml     # monitoring VM
│   ├── inventories/
│   │   └── inventory.ini      # группы app (web_servers) + monitoring
│   ├── playbooks/
│   │   ├── playbook.yml           # app VM
│   │   └── playbook-metrics.yml   # monitoring VM
│   └── roles/
│       ├── bulletins/         # деплой, Nginx, Certbot, UFW
│       ├── node_exporter/
│       ├── nginx_exporter/
│       ├── promtail/
│       ├── prometheus/
│       ├── loki/
│       └── grafana/
├── assets/
│   ├── README.md              # скриншоты дашбордов с пояснениями
│   └── monitoring/            # PNG, required-metrics.md
├── scripts/
│   └── smoke.sh
├── Makefile
├── README.md
└── requirements.yml             # Galaxy roles + collections
```

| Файл / каталог | Назначение |
|----------------|------------|
| `ansible/playbooks/playbook.yml` | Деплой приложения (web-сервер) |
| `ansible/playbooks/playbook-metrics.yml` | Prometheus + Loki + Grafana (monitoring-сервер) |
| `Makefile` | `make galaxy`, `make setup`, `make deploy`, `make metrics`, `make lint`, `make test`, `make smoke` |
| `scripts/smoke.sh` | Curl smoke-тесты приложения и мониторинга |
| `.ansible-lint` | Конфиг ansible-lint в `ansible/` (исключены Galaxy-роли) |
| `requirements.yml` | Galaxy roles (docker, nginx, certbot) и collections (community.docker, community.general) |
| `ansible/inventories/inventory.ini` | Web и monitoring хосты |
| `ansible/group_vars/web_servers.yml` | Домен, образ, S3, Nginx, мониторинг |
| `ansible/group_vars/monitoring.yml` | Prometheus, Grafana, scrape targets, firewall |
| `ansible/roles/bulletins/` | Деплой, Nginx, Certbot, UFW |
| `ansible/roles/node_exporter/` | Node Exporter (системные метрики) |
| `ansible/roles/nginx_exporter/` | nginx-prometheus-exporter (stub_status) |
| `ansible/roles/promtail/` | Promtail — сбор логов на web-сервере |
| `ansible/roles/loki/` | Loki в Docker на monitoring-сервере |
| `ansible/roles/prometheus/` | Prometheus в Docker |
| `ansible/roles/grafana/` | Grafana в Docker, provisioning, dashboards |
| `assets/` | Скриншоты дашбордов и пояснения — [`assets/README.md`](assets/README.md) |
| `assets/monitoring/` | PNG-скриншоты, [`required-metrics.md`](assets/monitoring/required-metrics.md) |

### Inventory

Две отдельные ВМ: **app** (приложение + Nginx + exporters + Promtail) и **monitoring** (Prometheus + Grafana + Loki). Группа `app` — алиас для `web_servers`.

Имена хостов в группах **должны быть уникальными** — иначе Ansible объединит их в один хост и возьмёт последний `ansible_host`:

```ini
[web_servers]
web ansible_host=138.16.178.207 ansible_user=root

[monitoring]
metrics ansible_host=138.16.187.61 ansible_user=root

[app:children]
web_servers
```

Секреты (DB, S3, registry OAuth, Grafana, Telegram) **не хранятся** в `group_vars` — только через переменные окружения / CI secrets / Vault (см. таблицу ниже).

## Требования

**Control node** (ваш компьютер):

- Python 3.12+, Ansible, ansible-lint (для `make lint`)
- `make galaxy` — установка **ролей** в `ansible/roles/` и **коллекций** (`community.docker`, `community.general`)
- SSH-доступ к серверам
- Переменные окружения с секретами (см. ниже)

**Web-сервер** (Ubuntu 22.04+):

- DNS A-запись `task.devops-campus.ru` → `138.16.178.207`
- Каталоги: `/var/lib/postgresql/bulletins`, `/var/log/bulletins`, `/var/www/bulletins`, `/var/www/letsencrypt`

**Monitoring-сервер** (Ubuntu 22.04+, группа `monitoring`):

- Docker-контейнеры Prometheus, **Loki** и Grafana в сети `monitoring`
- UFW: **22**, **9090** (Prometheus), **3000** (Grafana); **3100** (Loki push) — только с IP web-сервера
- Loki: volume данных `/var/lib/loki`, конфиг `/opt/loki/config`
- Prometheus: volume конфигов `/opt/prometheus/config`, данных `/var/lib/prometheus`
- Grafana: volume данных `/var/lib/grafana`, provisioning `/opt/grafana/provisioning`, dashboards `/opt/grafana/dashboards`
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
| `GRAFANA_ADMIN_PASSWORD` | `grafana_admin_password` | Пароль admin Grafana (CI secret / Vault) |
| `TELEGRAM_BOT_TOKEN` | `grafana_telegram_bot_token` | Токен Telegram-бота для алертов |
| `TELEGRAM_CHAT_ID` | `grafana_telegram_chat_id` | Chat ID получателя (строка) |
| `LOKI_BASIC_AUTH_USERNAME` | `promtail_loki_basic_auth_username` | Basic Auth Loki (опционально) |
| `LOKI_BASIC_AUTH_PASSWORD` | `promtail_loki_basic_auth_password` | Basic Auth Loki (опционально) |
| `ANSIBLE_PASSWORD` | `ansible_password` | SSH-пароль (опционально) |

`DOCKER_OAUTH_TOKEN` должен иметь доступ к registry `crpd2isbgl7k3puo75s1` — тому же, куда CI пушит образ.

## Развёртывание с нуля

Пошаговая процедура для проверяющего: от fork до работающего production и мониторинга.

### 1. Подготовка репозитория и ключей

```bash
# Fork этого репозитория и клонирование
git clone git@github.com:<your-user>/devops-engineer-from-scratch-project-318.git
cd devops-engineer-from-scratch-project-318

# Fork приложения (образ собирается CI там)
# https://github.com/EvgeniyMsk/project-devops-deploy

# SSH-ключ для Ansible (рекомендуется ed25519)
ssh-keygen -t ed25519 -C "ansible-deploy" -f ~/.ssh/devops_deploy -N ""
ssh-copy-id -i ~/.ssh/devops_deploy.pub root@138.16.178.207   # web
ssh-copy-id -i ~/.ssh/devops_deploy.pub root@138.16.187.61    # monitoring

# Проверка доступа
ssh -i ~/.ssh/devops_deploy root@138.16.178.207 'hostname'
ssh -i ~/.ssh/devops_deploy root@138.16.187.61 'hostname'
```

Убедитесь, что DNS A-запись `task.devops-campus.ru` указывает на `138.16.178.207`.

### 2. Секреты (переменные окружения / Vault)

Секреты **не коммитятся** в репозиторий. Передаются через env или Ansible Vault в CI.

| Группа | Переменные | Когда нужны |
|--------|------------|-------------|
| Web / deploy | `SPRING_DATASOURCE_*`, `STORAGE_S3_*`, `DOCKER_OAUTH_TOKEN` | `make setup`, `make deploy` |
| Monitoring | `GRAFANA_ADMIN_PASSWORD`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | `make metrics` |
| Опционально | `LOKI_BASIC_AUTH_*`, `ANSIBLE_PASSWORD` | Basic Auth Loki, SSH по паролю |

Пример локального экспорта:

```bash
export SPRING_DATASOURCE_USERNAME=postgres
export SPRING_DATASOURCE_PASSWORD='...'
export STORAGE_S3_ACCESSKEY='...'
export STORAGE_S3_SECRETKEY='...'
export DOCKER_OAUTH_TOKEN='...'

export GRAFANA_ADMIN_PASSWORD='...'
export TELEGRAM_BOT_TOKEN='...'
export TELEGRAM_CHAT_ID='...'
```

В GitHub Actions — Environment secrets с теми же именами.

### 3. Установка зависимостей и lint

```bash
pip install ansible ansible-lint   # control node
make galaxy                        # роли Galaxy (docker, nginx, certbot)
make lint                          # ansible-lint по кастомным ролям и плейбукам
make test                          # syntax-check + ansible ping всех хостов
```

### 4. Деплой web-сервера

```bash
make setup    # первичная настройка: Docker, UFW, Nginx, Certbot, БД, приложение, Promtail
make deploy   # обновление образа (повторные деплои)
```

Проверка домена:

```bash
curl -I https://task.devops-campus.ru
curl -s https://task.devops-campus.ru/api/bulletins | head
curl -sk https://task.devops-campus.ru:9090/actuator/health
```

### 5. Деплой monitoring-сервера

```bash
make metrics   # Prometheus, Loki, Grafana + provisioning, алерты → Telegram
```

Проверка мониторинга:

```bash
make smoke     # curl smoke-тесты с control node (см. ниже)
```

Или вручную:

- Prometheus targets UP: http://138.16.187.61:9090/targets
- Grafana dashboards: http://138.16.187.61:3000 (login `admin`)
- Logs Overview: http://138.16.187.61:3000/d/logs-overview
- Telegram: Contact points → Test или правило «Grafana test alert»

### 6. Ручная проверка алертов

1. **Telegram test:** Grafana → Alerting → Contact points → `telegram-alerts` → **Test**.
2. **Правило test alert:** снять Pause с «Grafana test alert» → дождаться Firing → вернуть Pause.
3. **Симуляция сбоя (осторожно):** `systemctl stop node_exporter` на web → через 5 мин «Node exporter missing».

Скриншот срабатывания сохраните в `assets/monitoring/alert_telegram.png`.

### 7. Порядок проверки результата

| # | Что проверить | Как |
|---|---------------|-----|
| 1 | App VM доступна | `make test` (ansible ping) |
| 2 | Приложение и REST | `make smoke` или `curl https://task.devops-campus.ru/api/bulletins` |
| 3 | Статика + HTTPS | браузер → https://task.devops-campus.ru |
| 4 | Метрики app VM | https://task.devops-campus.ru:9090/metrics , `/actuator/health` |
| 5 | Prometheus targets UP | http://138.16.187.61:9090/targets |
| 6 | Grafana dashboards | http://138.16.187.61:3000/d/system-resources (и др. в папке **Bulletins**) |
| 7 | Логи в Loki | Grafana → Explore → `{app="bulletins"}` или E2E из раздела «Логи» |
| 8 | Алерты Telegram | Contact points → Test или «Grafana test alert» |

## Справочник инфраструктуры

Единая таблица IP, URL, портов и каналов оповещений.

| Параметр | Значение |
|----------|----------|
| **Web-сервер IP** | `138.16.178.207` (inventory: `web`) |
| **Monitoring-сервер IP** | `138.16.187.61` (inventory: `metrics`) |
| **Домен приложения** | https://task.devops-campus.ru |
| **REST API** | https://task.devops-campus.ru/api/bulletins |
| **Метрики (HTTPS)** | https://task.devops-campus.ru:9090/metrics |
| **Actuator health** | https://task.devops-campus.ru:9090/actuator/health |
| **Nginx metrics** | https://task.devops-campus.ru:9090/nginx/metrics |
| **Prometheus UI** | http://138.16.187.61:9090 |
| **Prometheus targets** | http://138.16.187.61:9090/targets |
| **Grafana UI** | http://138.16.187.61:3000 (login: `admin`) |
| **Grafana dashboards** | http://138.16.187.61:3000/dashboards (папка **Bulletins**) |
| **Grafana alerts** | http://138.16.187.61:3000/alerting/list |
| **Loki API** | http://138.16.187.61:3100 (push только с web IP, UFW) |
| **Docker registry** | `cr.yandex/crpd2isbgl7k3puo75s1/project-devops-deploy` |
| **S3 bucket** | `hexlet-bucket` (`ru-central1`) |

### Порты (сводка)

| Сервер | Порт | Доступ | Назначение |
|--------|------|--------|------------|
| Web | 80, 443 | публично | HTTP/HTTPS приложение |
| Web | 9090 | monitoring + VPN | HTTPS метрики через Nginx |
| Web | 8080, 9091, 9100, 9113, 8082, 9080 | localhost | app, management, exporters, promtail |
| Monitoring | 22 | SSH | администрирование |
| Monitoring | 9090 | публично | Prometheus |
| Monitoring | 3000 | публично | Grafana |
| Monitoring | 3100 | только web IP | Loki push |

### Каналы оповещений

| Канал | Настройка | Переменные |
|-------|-----------|------------|
| **Telegram** | Grafana contact point `telegram-alerts` | `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` |
| **Email** | не используется | — |

Правила алертов: Grafana → папка **Bulletins** → группа `bulletins-alerts` (см. раздел «Алертинг»).

## Проверки (make lint / test / smoke)

| Команда | Что делает |
|---------|------------|
| `make lint` | `ansible-lint` по плейбукам и кастомным ролям (Galaxy-роли исключены) |
| `make test` | `ansible-playbook --syntax-check` + `ansible all -m ping` |
| `make smoke` | Curl-проверки: HTTPS app, REST API, Actuator, Prometheus, Grafana; Loki — если порт доступен |

```bash
make galaxy && make lint && make test && make smoke
```

Переменные для smoke (опционально):

```bash
WEB_HOST=138.16.178.207 METRICS_HOST=138.16.187.61 DOMAIN=task.devops-campus.ru make smoke
```

**Molecule:** в кастомных ролях не настроен; интеграционные проверки — через `make test` и `make smoke` против production inventory.

Loki с control node часто недоступен (UFW). Проверка с web-сервера:

```bash
cd ansible && ansible web -m shell -a \
  'curl -sf http://138.16.187.61:3100/ready && curl -sf -G "http://138.16.187.61:3100/loki/api/v1/labels" | head -c 120'
```

## Makefile — команды и порядок запуска

| Команда | Когда запускать | Нужные секреты | Плейбук / действие |
|---------|-----------------|----------------|-------------------|
| `make galaxy` | Первый запуск, после изменения `requirements.yml` | — | Установка Galaxy roles + collections |
| `make setup` | **Первичный** деплой app VM | `SPRING_DATASOURCE_*`, `STORAGE_S3_*`, `DOCKER_OAUTH_TOKEN` | `playbook.yml` (полный) |
| `make deploy` | Обновление образа приложения | те же | `playbook.yml` (теги deploy, certbot, nginx) |
| `make metrics` | **Первичный** или повторный деплой monitoring VM | `GRAFANA_ADMIN_PASSWORD`, `TELEGRAM_*` | `playbook-metrics.yml` |
| `make lint` | Перед PR / после правок Ansible | — | `ansible-lint` |
| `make test` | Проверка синтаксиса и SSH-доступа | — | syntax-check + `ansible ping` |
| `make smoke` | Проверка production после деплоя | — | `scripts/smoke.sh` |

**Рекомендуемый порядок с нуля:** `make galaxy` → экспорт секретов → `make setup` → проверка домена → экспорт metrics-секретов → `make metrics` → `make smoke`.

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

# Monitoring (секреты — CI / Vault, не в репозитории)
export GRAFANA_ADMIN_PASSWORD=...
export TELEGRAM_BOT_TOKEN=...
export TELEGRAM_CHAT_ID=...

# Первичная настройка web-сервера (Docker, UFW, Nginx, Certbot, БД, приложение)
make setup

# Обновление приложения
make deploy

# Откат на конкретный коммит (git SHA из CI)
make deploy ANSIBLE_DOCKER_TAG=<git-sha>

# Развёртывание Prometheus + Grafana на monitoring-сервере
make metrics

# Проверки
make lint
make test
make smoke
```

`make deploy` запускает теги `deploy,certbot,nginx`. Порядок задач в роли `bulletins`: **deploy → nginx → certbot** (сначала контейнеры, затем Nginx).

`make metrics` разворачивает стек мониторинга на ВМ `138.16.187.61`: UFW, Docker-сеть `monitoring`, Prometheus и Grafana с provisioning.

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
| `https://task.devops-campus.ru:9090/nginx/metrics` | nginx-prometheus-exporter | активные соединения, RPS (`nginx_*`) |
| `https://task.devops-campus.ru:9090/actuator/prometheus` | Spring Boot Actuator | JVM, HTTP, пул соединений БД |
| `https://task.devops-campus.ru:9090/actuator/health` | Spring Boot Actuator | Healthcheck |

Node Exporter и nginx-prometheus-exporter слушают `127.0.0.1` — снаружи недоступны. Nginx проксирует `/metrics` и `/nginx/metrics` на `:9090` (HTTPS, UFW allowlist: monitoring-сервер + VPN).

**Nginx stub_status** (внутренний endpoint для экспортера):

| Параметр | Значение |
|----------|----------|
| URI | `http://127.0.0.1:8082/nginx_status` |
| Конфиг | `/etc/nginx/conf.d/nginx-stub-status.conf` |
| Доступ | `127.0.0.1` + IP monitoring-сервера (`138.16.187.61`) + VPN |

```bash
# на web-сервере (localhost)
curl -s http://127.0.0.1:8082/nginx_status

# с monitoring-сервера (через HTTPS :9090, UFW allowlist)
curl -sk https://task.devops-campus.ru:9090/nginx/metrics | grep -E '^nginx_connections_active|^nginx_http_requests_total'
```

Дашборд: [Nginx Metrics](http://138.16.187.61:3000/d/nginx-metrics) — RPS, коды ответов (upstream), latency, активные соединения.

Алерт по 5xx (метрики): [High HTTP 5xx rate](http://138.16.187.61:3000/alerting/list). Алерт по логам: **Log 5xx spike (Loki)**.

### Логи (Loki + Promtail)

| Компонент | Где | Конфиг (Ansible) |
|-----------|-----|------------------|
| Promtail | web-сервер (`138.16.178.207`), systemd | `ansible/roles/promtail/templates/promtail.yml.j2` |
| Loki | monitoring-сервер, Docker | `ansible/roles/loki/templates/loki-config.yml.j2` |

**Promtail jobs и лейблы:** `job` (`docker`, `nginx-access`, `nginx-monitoring`, `application`), `env=prod`, `app=bulletins`, `host=<inventory_hostname>`.

| Источник | job | Формат |
|----------|-----|--------|
| Docker `application`, `database` | `docker` | JSON stdout (CRI + json pipeline) |
| `/var/log/bulletins/*.log` | `application` | JSON |
| `/var/log/nginx/bulletins-ssl-access.json` | `nginx-access` | JSON (`access_json`) |
| `/var/log/nginx/monitoring-access.json` | `nginx-monitoring` | JSON (`monitoring_json`) |

**Loki:** порт `3100` на monitoring-сервере, UFW — push только с IP web-сервера. Grafana подключается через Docker-сеть `monitoring` (`http://loki:3100`).

**Дашборд:** [Logs Overview](http://138.16.187.61:3000/d/logs-overview) — 5xx, latency p95, поиск по user/IP.

#### End-to-end проверка логов

```bash
# 1. Web-сервер — Promtail running
systemctl status promtail
curl -s http://127.0.0.1:9080/ready

# 2. Записать тестовый JSON-лог
echo '{"timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","level":"INFO","message":"promtail-e2e-test","user":"e2e-checker"}' \
  >> /var/log/bulletins/e2e-test.log

# или через Ansible (тег test_logging):
cd ansible && ansible-playbook playbooks/playbook.yml --tags=test_logging

# 3. Loki — запрос с monitoring-сервера (или web, если UFW разрешает)
curl -G "http://138.16.187.61:3100/loki/api/v1/query" \
  --data-urlencode 'query={app="bulletins"} |= "promtail-e2e-test"' \
  --data-urlencode 'limit=5'

# 4. Grafana Explore → Loki
# {app="bulletins"} |= "promtail-e2e-test"
```

**Сохранённые LogQL-запросы (дашборд Logs Overview):**

```logql
{job="nginx-access", app="bulletins"} | json | status >= 500
{job="nginx-access", app="bulletins"} | json | request_time > 1
{app="bulletins"} | json | message =~ "(?i).*e2e-checker.*"
```

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
  - job_name: nginx
    metrics_path: /nginx/metrics
    scheme: https
    targets:
      - "{{ prometheus_scrape_host }}"
```

Перед деплоем конфиг проверяется: `promtool check config` и `promtool check rules` (роль `prometheus`).

#### Проверка `up == 1`

1. Откройте [http://138.16.187.61:9090/targets](http://138.16.187.61:9090/targets).
2. Убедитесь, что таргеты в состоянии **UP**:
   - `node` → `https://task.devops-campus.ru:9090/metrics`
   - `bulletins-app` → `https://task.devops-campus.ru:9090/actuator/prometheus`
   - `nginx` → `https://task.devops-campus.ru:9090/nginx/metrics`

Через PromQL на странице `/graph`:

```promql
up
```

Ожидаемый результат: `up{job="node"} == 1`, `up{job="bulletins-app"} == 1`, `up{job="nginx"} == 1`.

Метрики Nginx:

```bash
curl -s 'http://138.16.187.61:9090/api/v1/query?query=nginx_connections_active' | python3 -m json.tool
curl -s 'http://138.16.187.61:9090/api/v1/query?query=nginx_http_requests_total' | python3 -m json.tool
```

Через API:

```bash
curl -s 'http://138.16.187.61:9090/api/v1/query?query=up' | python3 -m json.tool
```

### Grafana

**URL:** [http://138.16.187.61:3000](http://138.16.187.61:3000)

| Параметр | Значение |
|----------|----------|
| URL | http://138.16.187.61:3000 |
| Логин | `admin` |
| Пароль | значение `GRAFANA_ADMIN_PASSWORD` (CI secret / Vault) |

Datasource'ы подключаются через provisioning (`ansible/roles/grafana/templates/datasources.yml.j2`):

| Datasource | URL (из Docker-сети `monitoring`) | Статус |
|------------|-----------------------------------|--------|
| Prometheus | `http://prometheus:9090` | активен |
| Loki | `http://loki:3100` | активен |

Provisioned dashboards (папка **Bulletins**):

| Dashboard | UID | Содержимое |
|-----------|-----|------------|
| System Resources | `system-resources` | CPU load, память, диск, сеть — **job = node** |
| Application Health | `application-health` | uptime, JVM, HikariCP, GC |
| HTTP Status Codes | `http-codes` | HTTP rate/latency по кодам ответа |
| Status Page | `status-page` | Состояние сервисов, ресурсы, алерты |
| Nginx Metrics | `nginx-metrics` | RPS, соединения, коды/latency upstream |
| Logs Overview | `logs-overview` | LogQL: 5xx, latency, поиск по user/IP |

Скриншоты ключевых панелей:

Скриншоты ключевых панелей с пояснениями: **[`assets/README.md`](assets/README.md)**.

| Dashboard | Скриншот |
|-----------|----------|
| Status Page | [`assets/monitoring/status_page.png`](assets/monitoring/status_page.png) |
| System Resources | [`assets/monitoring/system_resourses.png`](assets/monitoring/system_resourses.png) |
| Application Health | [`assets/monitoring/application_health.png`](assets/monitoring/application_health.png) |
| HTTP Status Codes | [`assets/monitoring/status_codes.png`](assets/monitoring/status_codes.png) |
| Nginx Metrics | [`assets/monitoring/nginx_metrics.png`](assets/monitoring/nginx_metrics.png) |
| Logs Overview | [`assets/monitoring/logs_overview.png`](assets/monitoring/logs_overview.png) |
| Alert (Telegram) | [`assets/monitoring/alert_telegram.png`](assets/monitoring/alert_telegram.png) *(после теста алерта)* |

Подробнее по метрикам: [`assets/monitoring/required-metrics.md`](assets/monitoring/required-metrics.md).

#### Алертинг (Grafana → Telegram)

Канал уведомлений: **Telegram Bot** (бесплатный). Токен и chat ID передаются через env, не хранятся в репозитории.

**Где смотреть правила:**

| Ресурс | URL / путь |
|--------|------------|
| Alert rules (UI) | [Alerting → Alert rules](http://138.16.187.61:3000/alerting/list) |
| Contact points | [Alerting → Contact points](http://138.16.187.61:3000/alerting/notifications) |
| Status Page | [Dashboard Status Page](http://138.16.187.61:3000/d/status-page) |
| Provisioning (repo) | `ansible/roles/grafana/templates/alerting/` |

**Критичные сценарии** (папка **Bulletins**, группа `bulletins-alerts`):

| Правило | Условие | `for` | severity |
|---------|---------|-------|----------|
| Application target down | `up{job="bulletins-app"} < 1` | 5m | critical |
| Node exporter missing | `up{job="node"} < 1` | 5m | critical |
| High HTTP 5xx rate | 5xx > 0.05 req/s | 5m | critical |
| Log 5xx spike (Loki) | >10 записей 5xx/5m в access-log | 5m | critical |
| High CPU usage | CPU > 80% | 10m | warning |
| High memory usage | RAM > 90% | 10m | warning |
| Disk space low | disk > 85% | 10m | warning |
| Grafana test alert | `vector(1) > 0` | 0s | info (на паузе) |

Пороги и `for` настраиваются в `ansible/group_vars/monitoring.yml`.

**Настройка Telegram-бота:**

1. Создайте бота через [@BotFather](https://t.me/BotFather), получите `TELEGRAM_BOT_TOKEN`.
2. Узнайте `TELEGRAM_CHAT_ID` (личный чат или группа) — например через [@userinfobot](https://t.me/userinfobot).
3. Сохраните оба значения в CI secrets / Vault.
4. Выполните `make metrics`.

**Как триггернуть тестовый алерт:**

Способ 1 — тест contact point (без срабатывания правила):

1. Grafana → **Alerting** → **Contact points** → `telegram-alerts` → **Test**.

Способ 2 — правило `Grafana test alert`:

1. [Alert rules](http://138.16.187.61:3000/alerting/list) → `Grafana test alert` → снимите **Pause**.
2. Через ~1 мин правило перейдёт в **Firing**, сообщение придёт в Telegram.
3. Верните **Pause** после проверки.

Способ 3 — симуляция недоступности (осторожно, на production):

```bash
# на web-сервере — временно остановить node_exporter
systemctl stop node_exporter
# через 5+ минут сработает «Node exporter missing»
systemctl start node_exporter
```

**Обновление alert rules и дашбордов** (та же команда):

```bash
export GRAFANA_ADMIN_PASSWORD=...
export TELEGRAM_BOT_TOKEN=...
export TELEGRAM_CHAT_ID=...
make metrics
# или только Grafana:
cd ansible && ansible-playbook playbooks/playbook-metrics.yml --tags=prepare_grafana \
  -e grafana_admin_password="$GRAFANA_ADMIN_PASSWORD" \
  -e grafana_telegram_bot_token="$TELEGRAM_BOT_TOKEN" \
  -e grafana_telegram_chat_id="$TELEGRAM_CHAT_ID"
```

После теста сохраните скриншот срабатывания в `assets/monitoring/alert_telegram.png`.

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

Быстрая проверка с control node:

```bash
make smoke    # HTTPS, REST, метрики, Prometheus, Grafana
make test     # ansible ping + syntax-check
```

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
docker ps | grep -E 'prometheus|grafana'
ufw status

# Grafana
curl -s -o /dev/null -w "%{http_code}" http://138.16.187.61:3000/login
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
| nginx target DOWN | `systemctl status nginx_exporter`; `curl http://127.0.0.1:8082/nginx_status`; проверьте stub_status и `/nginx/metrics` |
| Loki / Promtail — нет логов | `systemctl status promtail`; `curl http://127.0.0.1:9080/ready`; UFW :3100 с web-сервера; `curl http://138.16.187.61:3100/ready` |
| Grafana «No data» | Для **System Resources** выберите `job=node`; для приложения — `job=bulletins-app`. Проверьте [Prometheus targets](http://138.16.187.61:9090/targets) (оба UP) |
| Telegram не приходит | Проверьте `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`; chat ID — строка в кавычках; Contact points → Test |
| `GRAFANA_ADMIN_PASSWORD is not set` | Экспортируйте пароль перед `make metrics` |

## Откат

CI публикует тег `<git-sha>` для каждого коммита в `main`:

```bash
make deploy ANSIBLE_DOCKER_TAG=f4bd182c279d1929d623dd4ed669345a5a59da3b
```

SHA смотрите в [Actions](https://github.com/EvgeniyMsk/project-devops-deploy/actions) или в логах job `docker`.
