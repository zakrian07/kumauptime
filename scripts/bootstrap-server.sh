#!/usr/bin/env bash
# One-time prep for a fresh Ubuntu/Debian server: install Docker Engine + the
# compose plugin and configure UFW (SSH/HTTP/HTTPS). Idempotent — safe to re-run.
# Run as root ON THE TARGET SERVER:  sudo bash scripts/bootstrap-server.sh
# Review before running. Uses Docker's official get.docker.com convenience script.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root: sudo $0" >&2
	exit 1
fi

if command -v docker >/dev/null 2>&1; then
	echo "==> Docker already installed: $(docker --version)"
else
	echo "==> Installing Docker (get.docker.com)"
	curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
	sh /tmp/get-docker.sh
	rm -f /tmp/get-docker.sh
fi

if command -v ufw >/dev/null 2>&1; then
	echo "==> Configuring UFW (allowing SSH before enabling to avoid lockout)"
	ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp
	ufw allow 80/tcp
	ufw allow 443/tcp
	ufw allow 443/udp          # HTTP/3 (QUIC) — Caddy publishes 443/udp
	ufw --force enable
	ufw status verbose
else
	echo "WARN: ufw not found; skipping firewall setup. Secure 22/80/443 another way." >&2
fi

echo "==> Done. Next: copy this project to the server, fill .env, run scripts/deploy.sh"
