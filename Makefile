SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help render validate up down restart logs ps pull deploy backup watchdog hash

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

render: ## Render caddy/Caddyfile from template + .env + admin.hash
	./scripts/render-caddyfile.sh

validate: render ## Render, then validate docker-compose.yml + Caddyfile
	docker compose config -q
	docker run --rm -v "$$PWD/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" caddy:2 caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile

up: render ## Render, start the stack, and reload Caddy to apply config
	docker compose up -d
	docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || docker compose up -d --force-recreate caddy

down: ## Stop and remove containers (keeps volumes)
	docker compose down

restart: render ## Render, then restart the stack (re-reads config on boot)
	docker compose restart

logs: ## Tail logs
	docker compose logs -f --tail=100

ps: ## Show container status
	docker compose ps

pull: ## Pull latest images
	docker compose pull

deploy: ## Validate + pull + up (scripts/deploy.sh)
	./scripts/deploy.sh

backup: ## Back up Kuma data + Caddy certs
	./scripts/backup.sh

watchdog: ## Run the watchdog check once
	./scripts/watchdog.sh

hash: ## Set the admin password (prompts; writes caddy/admin.hash)
	./scripts/set-admin-password.sh
