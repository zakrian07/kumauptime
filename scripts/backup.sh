#!/usr/bin/env bash
# Back up Kuma data (monitors, status pages, history, settings) and Caddy certs
# to timestamped tarballs under ./backups/. Keeps the newest $KEEP of each.
# Assumes GNU coreutils (the Linux host). Run from cron for daily backups.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

KEEP="${KEEP:-14}"
BACKUP_DIR="$PWD/backups"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"

backup_one() {
	# $1 = container name, $2 = path inside container, $3 = archive name prefix
	local container="$1" src="$2" prefix="$3"
	if ! docker inspect "$container" >/dev/null 2>&1; then
		echo "WARN: container '$container' not found; skipping $prefix" >&2
		return 0
	fi
	echo "==> Backing up $container:$src -> $prefix-$TS.tar.gz"
	docker run --rm \
		--volumes-from "$container" \
		-v "$BACKUP_DIR:/backup" \
		alpine tar czf "/backup/${prefix}-${TS}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")"

	# Rotate: keep newest $KEEP (filenames sort chronologically by their UTC stamp).
	find "$BACKUP_DIR" -maxdepth 1 -name "${prefix}-*.tar.gz" | sort | head -n "-${KEEP}" | xargs -r rm -f
}

backup_one kuma  /app/data "kuma-data"
backup_one caddy /data     "caddy-data"

echo "==> Done. Current backups:"
ls -lh "$BACKUP_DIR"
