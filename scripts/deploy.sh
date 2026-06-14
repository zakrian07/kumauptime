#!/usr/bin/env bash
# Validate config, pull images, and (re)start the stack. Idempotent — safe to re-run.
# Run from the project root or anywhere: it cd's to the repo root itself.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -f .env ]]; then
	echo "ERROR: .env not found. Copy .env.example to .env and fill it in." >&2
	exit 1
fi

echo "==> Rendering Caddyfile from template"
./scripts/render-caddyfile.sh

echo "==> Validating compose config"
docker compose config -q

echo "==> Validating Caddyfile"
docker run --rm \
	-v "$PWD/caddy/Caddyfile:/etc/caddy/Caddyfile:ro" \
	caddy:2 caddy validate --adapter caddyfile --config /etc/caddy/Caddyfile

echo "==> Pulling images"
docker compose pull

echo "==> Starting stack"
docker compose up -d

# A changed bind-mounted Caddyfile does NOT trigger container recreation, so the
# running Caddy keeps serving its startup config. Reload it in place (zero-downtime);
# fall back to recreate if Caddy isn't running yet (e.g. first boot edge cases).
echo "==> Reloading Caddy to apply the rendered config"
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
	|| docker compose up -d --force-recreate caddy

echo "==> Pruning dangling images"
docker image prune -f

echo "==> Status"
docker compose ps
