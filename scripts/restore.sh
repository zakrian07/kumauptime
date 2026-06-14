#!/usr/bin/env bash
# Restore a Kuma data backup into the volume. Stops Kuma, wipes current data,
# extracts the tarball, restarts. DESTRUCTIVE — prompts for confirmation.
# Usage: scripts/restore.sh backups/kuma-data-YYYYMMDDTHHMMSSZ.tar.gz
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ARCHIVE="${1:-}"
if [[ -z "$ARCHIVE" || ! -f "$ARCHIVE" ]]; then
	echo "Usage: $0 <path-to-kuma-data-backup.tar.gz>" >&2
	exit 1
fi
ARCHIVE="$(realpath "$ARCHIVE")"

read -r -p "This OVERWRITES current Kuma data with $ARCHIVE. Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { echo "Aborted."; exit 1; }

# Safety net: always bring Kuma back, even if the restore aborts partway.
trap 'docker compose start uptime-kuma >/dev/null 2>&1 || true' EXIT

echo "==> Stopping Kuma"
docker compose stop uptime-kuma

# Extract to a staging dir and VERIFY it before wiping current data, so a corrupt
# or truncated tarball can never leave /app/data half-deleted. (Residual risk: a
# failure during the final copy — e.g. disk full — leaves data partial; the trap
# still restarts Kuma and the script exits non-zero.)
echo "==> Restoring (extract + verify, then swap)"
docker run --rm \
	--volumes-from kuma \
	-v "$ARCHIVE:/restore.tar.gz:ro" \
	alpine sh -ec '
		rm -rf /staging && mkdir -p /staging
		tar xzf /restore.tar.gz -C /staging
		test -d /staging/data
		rm -rf /app/data/* /app/data/.[!.]* 2>/dev/null || true
		cp -a /staging/data/. /app/data/
		rm -rf /staging
	'

echo "==> Restore complete; Kuma is being (re)started by the exit handler."
