ANSIBLE_DIR := ansible
ANSIBLE_PLAYBOOK := playbooks/playbook.yml

DOCKER_IMAGE ?= project-devops-deploy
DOCKER_TAG ?= latest
ANSIBLE_DOCKER_TAG ?= $(DOCKER_TAG)

galaxy:
	ansible-galaxy install -r requirements.yml -p $(ANSIBLE_DIR)/roles
	ansible-galaxy collection install -r requirements.yml

# Secrets are passed via environment variables (GitHub Environment secrets in CI).
ANSIBLE_SECRET_VARS = \
	-e spring_datasource_username="$(SPRING_DATASOURCE_USERNAME)" \
	-e spring_datasource_password="$(SPRING_DATASOURCE_PASSWORD)" \
	-e storage_s3_accesskey="$(STORAGE_S3_ACCESSKEY)" \
	-e storage_s3_secretkey="$(STORAGE_S3_SECRETKEY)" \
	-e docker_oauth_token="$(DOCKER_OAUTH_TOKEN)"

ifneq ($(strip $(ANSIBLE_PASSWORD)),)
ANSIBLE_SECRET_VARS += -e ansible_password="$(ANSIBLE_PASSWORD)"
endif

METRICS_SECRET_VARS = \
	-e grafana_admin_password="$(GRAFANA_ADMIN_PASSWORD)" \
	-e grafana_telegram_bot_token="$(TELEGRAM_BOT_TOKEN)" \
	-e grafana_telegram_chat_id="$(TELEGRAM_CHAT_ID)"

ifneq ($(strip $(LOKI_BASIC_AUTH_USERNAME)),)
METRICS_SECRET_VARS += \
	-e promtail_loki_basic_auth_username="$(LOKI_BASIC_AUTH_USERNAME)" \
	-e promtail_loki_basic_auth_password="$(LOKI_BASIC_AUTH_PASSWORD)"
ANSIBLE_SECRET_VARS += \
	-e promtail_loki_basic_auth_username="$(LOKI_BASIC_AUTH_USERNAME)" \
	-e promtail_loki_basic_auth_password="$(LOKI_BASIC_AUTH_PASSWORD)"
endif

define require_metrics_secrets
	@test -n "$(GRAFANA_ADMIN_PASSWORD)" || (echo "GRAFANA_ADMIN_PASSWORD is not set" && exit 1)
	@test -n "$(TELEGRAM_BOT_TOKEN)" || (echo "TELEGRAM_BOT_TOKEN is not set" && exit 1)
	@test -n "$(TELEGRAM_CHAT_ID)" || (echo "TELEGRAM_CHAT_ID is not set" && exit 1)
endef

define require_deploy_secrets
	@test -n "$(SPRING_DATASOURCE_USERNAME)" || (echo "SPRING_DATASOURCE_USERNAME is not set" && exit 1)
	@test -n "$(SPRING_DATASOURCE_PASSWORD)" || (echo "SPRING_DATASOURCE_PASSWORD is not set" && exit 1)
	@test -n "$(STORAGE_S3_ACCESSKEY)" || (echo "STORAGE_S3_ACCESSKEY is not set" && exit 1)
	@test -n "$(STORAGE_S3_SECRETKEY)" || (echo "STORAGE_S3_SECRETKEY is not set" && exit 1)
	@test -n "$(DOCKER_OAUTH_TOKEN)" || (echo "DOCKER_OAUTH_TOKEN is not set" && exit 1)
endef

setup: galaxy
	$(require_deploy_secrets)
	cd $(ANSIBLE_DIR) && ansible-playbook $(ANSIBLE_PLAYBOOK) $(ANSIBLE_SECRET_VARS)

deploy: galaxy
	$(require_deploy_secrets)
	cd $(ANSIBLE_DIR) && ansible-playbook $(ANSIBLE_PLAYBOOK) -t deploy,certbot,nginx \
		-e docker_tag=$(ANSIBLE_DOCKER_TAG) \
		$(ANSIBLE_SECRET_VARS)

metrics: galaxy
	$(require_metrics_secrets)
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/playbook-metrics.yml --tags=monitoring \
		$(METRICS_SECRET_VARS)

lint: galaxy
	cd $(ANSIBLE_DIR) && ansible-lint playbooks/playbook.yml playbooks/playbook-metrics.yml \
		roles/bulletins roles/prometheus roles/grafana roles/loki roles/promtail \
		roles/node_exporter roles/nginx_exporter

test: galaxy
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/playbook.yml --syntax-check
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/playbook-metrics.yml --syntax-check
	cd $(ANSIBLE_DIR) && ansible all -m ping

smoke:
	chmod +x scripts/smoke.sh
	./scripts/smoke.sh

.PHONY: galaxy setup deploy metrics lint test smoke
