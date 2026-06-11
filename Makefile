test:
	./gradlew test

start: run

run:
	./gradlew bootRun

update-gradle:
	./gradlew wrapper --gradle-version 9.2.1

update-deps:
	./gradlew refreshVersions

install:
	./gradlew dependencies

build:
	./gradlew build

lint:
	./gradlew spotlessCheck

lint-fix:
	./gradlew spotlessApply

DOCKER_IMAGE ?= project-devops-deploy
DOCKER_TAG ?= latest
ANSIBLE_DOCKER_TAG ?= $(DOCKER_TAG)

docker-build:
	docker build -t $(DOCKER_IMAGE):$(DOCKER_TAG) .

docker-run:
	docker run --rm -p 8080:8080 -p 9090:9090 $(DOCKER_IMAGE):$(DOCKER_TAG)

docker-start: docker-build docker-run

galaxy:
	ansible-galaxy install -r requirements.yml

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

define require_deploy_secrets
	@test -n "$(SPRING_DATASOURCE_USERNAME)" || (echo "SPRING_DATASOURCE_USERNAME is not set" && exit 1)
	@test -n "$(SPRING_DATASOURCE_PASSWORD)" || (echo "SPRING_DATASOURCE_PASSWORD is not set" && exit 1)
	@test -n "$(STORAGE_S3_ACCESSKEY)" || (echo "STORAGE_S3_ACCESSKEY is not set" && exit 1)
	@test -n "$(STORAGE_S3_SECRETKEY)" || (echo "STORAGE_S3_SECRETKEY is not set" && exit 1)
	@test -n "$(DOCKER_OAUTH_TOKEN)" || (echo "DOCKER_OAUTH_TOKEN is not set" && exit 1)
endef

setup: galaxy
	$(require_deploy_secrets)
	ansible-playbook playbook.yml $(ANSIBLE_SECRET_VARS)

deploy: galaxy
	$(require_deploy_secrets)
	ansible-playbook playbook.yml -t deploy,certbot,nginx \
		-e docker_tag=$(ANSIBLE_DOCKER_TAG) \
		$(ANSIBLE_SECRET_VARS)

.PHONY: test start run update-gradle update-deps install build lint lint-fix \
	docker-build docker-run docker-start galaxy setup deploy
