#!/usr/bin/env bash
# Smoke-тесты production: приложение, метрики, Grafana, Loki (если доступен).
set -eu

WEB_HOST="${WEB_HOST:-138.16.178.207}"
METRICS_HOST="${METRICS_HOST:-138.16.187.61}"
DOMAIN="${DOMAIN:-task.devops-campus.ru}"

pass=0
fail=0
skip=0

check() {
  local name="$1"
  shift
  printf '==> %-40s ' "$name"
  if "$@"; then
    echo "OK"
    pass=$((pass + 1))
  else
    echo "FAIL"
    fail=$((fail + 1))
  fi
}

check_body_grep() {
  local url="$1" pattern="$2"
  shift 2
  local body
  body="$(curl "$@" --connect-timeout 10 "$url")"
  grep -qE "$pattern" <<< "$body"
}

check_skip() {
  local name="$1"
  printf '==> %-40s SKIP (%s)\n' "$name" "$2"
  skip=$((skip + 1))
}

echo "Smoke tests: domain=${DOMAIN} web=${WEB_HOST} metrics=${METRICS_HOST}"
echo

check "HTTPS приложение" curl -sfI --connect-timeout 10 "https://${DOMAIN}/" >/dev/null
check "REST API /api/bulletins" curl -sf --connect-timeout 10 "https://${DOMAIN}/api/bulletins" -o /dev/null
check "Статика (index.html)" check_body_grep "https://${DOMAIN}/" '[Hh][Tt][Mm][Ll]' -sf
check "Actuator health (9090)" check_body_grep "https://${DOMAIN}:9090/actuator/health" '"status"' -skf
check "Node metrics (9090)" check_body_grep "https://${DOMAIN}:9090/metrics" '^node_' -skf
check "Nginx metrics (9090)" check_body_grep "https://${DOMAIN}:9090/nginx/metrics" '^nginx_' -skf
check "Prometheus healthy" curl -sf --connect-timeout 10 "http://${METRICS_HOST}:9090/-/healthy" >/dev/null
check "Prometheus up query" check_body_grep "http://${METRICS_HOST}:9090/api/v1/query?query=up" '"status":"success"' -sf
check "Grafana login page" test "$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 10 "http://${METRICS_HOST}:3000/login")" = 200

if curl -sf --connect-timeout 5 "http://${METRICS_HOST}:3100/ready" >/dev/null 2>&1; then
  check "Loki ready" curl -sf --connect-timeout 10 "http://${METRICS_HOST}:3100/ready" >/dev/null
  check "Loki query" check_body_grep "http://${METRICS_HOST}:3100/loki/api/v1/labels" '"status":"success"' -sf -G
else
  check_skip "Loki ready" "порт 3100 доступен только с web-сервера (UFW)"
  check_skip "Loki query" "порт 3100 доступен только с web-сервера (UFW)"
fi

echo
echo "Result: ${pass} passed, ${fail} failed, ${skip} skipped"
if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
