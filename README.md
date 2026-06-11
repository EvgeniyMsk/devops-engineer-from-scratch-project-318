### Hexlet tests and linter status:
[![Actions Status](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-318/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/EvgeniyMsk/devops-engineer-from-scratch-project-318/actions)

# DevOps Engineer — Ansible Deployment

**Production:** [https://task.devops-campus.ru](https://task.devops-campus.ru)

Ansible-плейбуки для развёртывания [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy) на сервере Yandex Cloud.

В этом репозитории — **только инфраструктура и деплой**. Код приложения, `Dockerfile` и CI — в [форке приложения](https://github.com/EvgeniyMsk/project-devops-deploy).

## Репозитории

| Репозиторий | Содержимое |
|-------------|------------|
| [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy) | Java + React, Docker-образ, GitHub Actions |
| **devops-engineer-from-scratch-project-318** (этот) | Ansible, Nginx, Certbot, Node Exporter, деплой |

## Архитектура

```text
Internet
   │
   ▼
Nginx (:80 / :443)              task.devops-campus.ru
   │  static: /var/www/bulletins
   │  proxy app:     127.0.0.1:8080
   │  proxy actuator: 127.0.0.1:9090  (/actuator/health, /actuator/prometheus)
   ▼
application (Docker)            Spring Boot, prod profile
   │  logs: /var/log/bulletins
   │  management: :9090
   ▼
database (postgres:14)          PostgreSQL
   │  data: /var/lib/postgresql/bulletins
   ▼
Yandex Object Storage           изображения объявлений (S3)

Prometheus (внешний)
   ├── scrape :9100/metrics        Node Exporter (localhost)
   └── scrape /actuator/prometheus Spring Boot через Nginx (HTTPS)
```

| Компонент | Значение |
|-----------|----------|
| Сервер | `138.16.178.207` (`ansible/inventories/inventory.ini`) |
| Домен | `task.devops-campus.ru` |
| Docker-образ | `cr.yandex/crpd2isbgl7k3puo75s1/project-devops-deploy` |
| Тег по умолчанию | `latest` |
| PostgreSQL | `postgres:14` |
| S3 bucket | `hexlet-bucket` (`ru-central1`) |
| Registry | `cr.yandex` (логин: `oauth`) |

Образ собирается и публикуется CI в репозитории приложения. **Registry ID в Ansible должен совпадать с CI** (`ansible/group_vars/web_servers.yml` → `docker_image`).

## Структура

| Файл / каталог | Назначение |
|----------------|------------|
| `ansible/playbooks/playbook.yml` | Главный плейбук |
| `Makefile` | `make galaxy`, `make setup`, `make deploy` |
| `requirements.yml` | Роли Galaxy: docker, nginx, certbot |
| `ansible/inventories/inventory.ini` | Хост и SSH |
| `ansible/group_vars/web_servers.yml` | Домен, образ, S3, Nginx, мониторинг |
| `ansible/roles/bulletins/` | Деплой, Nginx, Certbot, firewall |
| `ansible/roles/node_exporter/` | Node Exporter (системные метрики) |
| `assets/monitoring/` | Документация обязательных метрик |

## Требования

**Control node** (ваш компьютер):

- Python 3.12+, Ansible
- `make galaxy` — установка ролей и коллекций из `requirements.yml`
- SSH-доступ к серверу
- Переменные окружения с секретами (см. ниже)

**Target server** (Ubuntu 22.04+):

- Порты 80, 443 — публично; 8080, 9090, 9100 — только `127.0.0.1` (Actuator и Node Exporter доступны снаружи через Nginx)
- DNS A-запись `task.devops-campus.ru` → IP сервера
- Каталоги: `/var/lib/postgresql/bulletins`, `/var/log/bulletins`, `/var/www/bulletins`, `/var/www/letsencrypt`

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

# Первичная настройка сервера (Docker, UFW, Nginx, Certbot, БД, приложение)
make setup

# Обновление приложения
make deploy

# Откат на конкретный коммит (git SHA из CI)
make deploy ANSIBLE_DOCKER_TAG=<git-sha>
```

`make deploy` запускает теги `deploy,certbot,nginx`.

## Процесс деплоя

При `make deploy` Ansible:

1. Логинится в Yandex Container Registry (`docker_oauth_token`).
2. Скачивает образы PostgreSQL и приложения (`community.docker.docker_image`).
3. Пересоздаёт контейнеры `database` и `application`.
4. Извлекает frontend static из JAR в `/var/www/bulletins`.
5. Обновляет Nginx и Certbot.

Тег образа: `docker_tag` в `web_servers.yml` (по умолчанию `latest`) или `ANSIBLE_DOCKER_TAG` при вызове `make deploy`.

## Мониторинг

### Источники метрик

| Источник | Endpoint | Назначение |
|----------|----------|------------|
| Node Exporter | `http://127.0.0.1:9100/metrics` | CPU, память, диски, сеть, процессы, systemd |
| Spring Boot Actuator | `https://task.devops-campus.ru/actuator/prometheus` | JVM, HTTP, пул соединений БД |
| Healthcheck | `https://task.devops-campus.ru/actuator/health` | Состояние приложения |

Nginx проксирует `/actuator/health` и `/actuator/prometheus` на management-порт приложения (`9090`). Запросы к этим путям логируются в JSON:

- access: `/var/log/nginx/monitoring-access.json` — JSON (`monitoring_json`)
- error: `/var/log/nginx/monitoring-error.json` — nginx error log (уровень `warn`; ошибки upstream также видны в JSON access-логе по полю `status`)

Подробнее: [`assets/monitoring/required-metrics.md`](assets/monitoring/required-metrics.md).

### Обязательные метрики для Prometheus

| Категория | Метрика | Источник | Описание |
|-----------|---------|----------|----------|
| **CPU load** | `node_load1` | Node Exporter | Средняя нагрузка за 1 минуту |
| **CPU load** | `node_load5` | Node Exporter | Средняя нагрузка за 5 минут |
| **CPU load** | `node_load15` | Node Exporter | Средняя нагрузка за 15 минут |
| **CPU load** | `node_cpu_seconds_total` | Node Exporter | Время CPU по режимам (idle, user, system, iowait) |
| **Память** | `node_memory_MemAvailable_bytes` | Node Exporter | Доступная оперативная память |
| **Память** | `node_memory_MemTotal_bytes` | Node Exporter | Общий объём RAM |
| **Память** | `node_memory_SwapFree_bytes` | Node Exporter | Свободный swap |
| **Диски** | `node_filesystem_avail_bytes` | Node Exporter | Свободное место на файловых системах |
| **Диски** | `node_filesystem_size_bytes` | Node Exporter | Размер файловых систем |
| **Диски** | `node_disk_read_bytes_total` | Node Exporter | Прочитано с диска |
| **Диски** | `node_disk_written_bytes_total` | Node Exporter | Записано на диск |
| **Сеть** | `node_network_receive_bytes_total` | Node Exporter | Входящий трафик по интерфейсам |
| **Сеть** | `node_network_transmit_bytes_total` | Node Exporter | Исходящий трафик по интерфейсам |
| **Сеть** | `node_netstat_Tcp_CurrEstab` | Node Exporter | Активные TCP-соединения |
| **Процессы** | `node_procs_running` | Node Exporter | Число запущенных процессов |
| **Процессы** | `node_procs_blocked` | Node Exporter | Заблокированные процессы |
| **Системные сервисы** | `node_systemd_unit_state` | Node Exporter | Состояние unit'ов (`nginx`, `docker`, `node_exporter`, …) |
| **Приложение** | `process_uptime_seconds` | Actuator | Uptime JVM |
| **Приложение** | `jvm_memory_used_bytes` | Actuator | Использование памяти JVM |
| **Приложение** | `jvm_gc_pause_seconds_count` | Actuator | Количество пауз GC |
| **Приложение** | `http_server_requests_seconds_count` | Actuator | Число HTTP-запросов |
| **Приложение** | `http_server_requests_seconds_sum` | Actuator | Суммарное время обработки запросов |
| **Приложение** | `http_server_requests_seconds_max` | Actuator | Максимальная латентность запроса |

### Пример scrape_config

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

## Проверка production

```bash
# На сервере
docker ps
docker logs application --tail 30
docker logs database --tail 10
curl -s http://127.0.0.1:8080/api/bulletins
curl -I https://task.devops-campus.ru
certbot certificates

# Мониторинг
curl -s http://127.0.0.1:9100/metrics | grep -E '^node_load1|^node_memory_MemAvailable'
curl -s http://127.0.0.1:9090/actuator/prometheus | grep -E '^process_uptime_seconds|^http_server_requests'
curl -s https://task.devops-campus.ru/actuator/health
curl -s https://task.devops-campus.ru/actuator/prometheus | head
tail -f /var/log/nginx/monitoring-access.json
systemctl status node_exporter
```

## Типичные проблемы

| Ошибка | Решение |
|--------|---------|
| `Registry ... not found` | Проверьте `docker_image` в `web_servers.yml` — должен совпадать с CI (`crpd2isbgl7k3puo75s1`) |
| `pull is of type str ... always` | Обновите коллекции: `make galaxy` или `ansible-galaxy collection install -r requirements.yml --force` |
| Образ не найден | Убедитесь, что CI job `docker` в [project-devops-deploy](https://github.com/EvgeniyMsk/project-devops-deploy/actions) прошёл успешно |
| 401 при pull | Проверьте `DOCKER_OAUTH_TOKEN` — тот же токен, что в GitHub Secrets для registry |

## Откат

CI публикует тег `<git-sha>` для каждого коммита в `main`:

```bash
make deploy ANSIBLE_DOCKER_TAG=f4bd182c279d1929d623dd4ed669345a5a59da3b
```

SHA смотрите в [Actions](https://github.com/EvgeniyMsk/project-devops-deploy/actions) или в логах job `docker`.