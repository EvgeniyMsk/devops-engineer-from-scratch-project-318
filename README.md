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
| **devops-engineer-from-scratch-project-315** (этот) | `playbook.yml`, inventory, Nginx, Certbot, деплой |

## Архитектура

```text
Internet
   │
   ▼
Nginx (:80 / :443)              task.devops-campus.ru
   │  static: /var/www/bulletins
   │  proxy: 127.0.0.1:8080
   ▼
application (Docker)            Spring Boot, prod profile
   │  logs: /var/log/bulletins
   ▼
database (postgres:14)          PostgreSQL
   │  data: /var/lib/postgresql/bulletins
   ▼
Yandex Object Storage           изображения объявлений (S3)
```

| Компонент | Значение |
|-----------|----------|
| Сервер | `138.16.178.207` (`inventory/inventory.ini`) |
| Домен | `task.devops-campus.ru` |
| Docker-образ | `cr.yandex/crpd2isbgl7k3puo75s1/project-devops-deploy` |
| Тег по умолчанию | `latest` |
| PostgreSQL | `postgres:14` |
| S3 bucket | `hexlet-bucket` (`ru-central1`) |
| Registry | `cr.yandex` (логин: `oauth`) |

Образ собирается и публикуется CI в репозитории приложения. **Registry ID в Ansible должен совпадать с CI** (`inventory/group_vars/web_servers.yml` → `docker_image`).

## Структура

| Файл / каталог | Назначение |
|----------------|------------|
| `playbook.yml` | Главный плейбук |
| `Makefile` | `make galaxy`, `make setup`, `make deploy` |
| `inventory/inventory.ini` | Хост и SSH |
| `inventory/group_vars/web_servers.yml` | Домен, образ, S3, Nginx |
| `requirements.yml` | Роли: docker, nginx, certbot; коллекция `community.docker` |
| `tasks/` | firewall, packages, nginx, certbot, deploy |
| `templates/` | Конфигурация Nginx |

## Требования

**Control node** (ваш компьютер):

- Python 3.12+, Ansible
- `make galaxy` — установка ролей и коллекций из `requirements.yml`
- SSH-доступ к серверу
- Переменные окружения с секретами (см. ниже)

**Target server** (Ubuntu 22.04+):

- Порты 80, 443 — публично; 8080, 9090 — только `127.0.0.1`
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

## Проверка production

```bash
# На сервере
docker ps
docker logs application --tail 30
docker logs database --tail 10
curl -s http://127.0.0.1:8080/api/bulletins
curl -I https://task.devops-campus.ru
certbot certificates
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