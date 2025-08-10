SHELL := /bin/bash
COMPOSE := docker compose

# ใช้ env จาก .env ของคุณ
POSTGRES_USER ?= crimeai
POSTGRES_DB ?= crime_ai
API_HOST ?= api.crimeai.local

.PHONY: up build test apply-indexes logs down restart ps

up:
	$(COMPOSE) up -d

build:
	$(COMPOSE) build $(if $(NO_CACHE),--no-cache,)

# ทดสอบสุขภาพ API ผ่าน Traefik host (HTTP 200 จาก /health)
test:
	@set -e; \
	url="http://$(API_HOST)/health"; \
	echo ">> Probing $$url"; \
	for i in $$(seq 1 20); do \
	  code=$$(curl -sS -o /dev/null -w "%{http_code}" $$url || true); \
	  if [ "$$code" = "200" ]; then \
	    echo "OK: $$url => 200"; exit 0; \
	  fi; \
	  echo "waiting... ($$i) got $$code"; \
	  sleep 2; \
	done; \
	echo "FAIL: $$url not healthy"; exit 1

# ต้องมีไฟล์ sql/indexes.sql และแมป ./sql:/sql:ro ไว้ใน docker-compose.yml
apply-indexes:
	@echo ">> Applying indexes from sql/indexes.sql"
	@$(COMPOSE) exec -T db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB) -f /sql/indexes.sql
	@echo ">> Done."

logs:
	$(COMPOSE) logs -f --tail=200

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

ps:
	$(COMPOSE) ps

