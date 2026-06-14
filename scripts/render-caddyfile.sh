#!/usr/bin/env bash
# Render caddy/Caddyfile from caddy/Caddyfile.tmpl using values from .env and the
# bcrypt admin hash in caddy/admin.hash.
#
# Why render instead of Caddy's {$VAR} + env_file: Docker Compose interpolates
# env-file VALUES, so a bcrypt hash's many '$' chars get mangled before Caddy ever
# sees them. Pure-bash ${var//pat/repl} substitution inserts values LITERALLY (no
# re-expansion of '$', '/', '.'), so the hash survives intact. The generated
# caddy/Caddyfile is gitignored.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

TMPL="caddy/Caddyfile.tmpl"
OUT="caddy/Caddyfile"
HASH_FILE="caddy/admin.hash"

[[ -f .env ]]        || { echo "ERROR: .env not found. Copy .env.example to .env." >&2; exit 1; }
[[ -f "$TMPL" ]]     || { echo "ERROR: $TMPL not found." >&2; exit 1; }
if [[ -d "$OUT" ]]; then
	# Docker creates a DIRECTORY at the bind-mount path if you `up` before rendering.
	echo "ERROR: $OUT is a directory (you ran 'docker compose up' before rendering)." >&2
	echo "       Remove it, then re-run: rm -rf '$OUT'  (may need sudo — Docker made it as root)" >&2
	exit 1
fi
if [[ ! -f "$HASH_FILE" ]]; then
	echo "ERROR: $HASH_FILE not found. Generate it (one line, bcrypt hash only):" >&2
	echo "  make hash PW='your-strong-password'" >&2
	echo "  # or: docker run --rm caddy:2 caddy hash-password --plaintext 'pw' > $HASH_FILE" >&2
	exit 1
fi

# Read .env keys literally (no `source`: avoids executing a malformed .env and
# avoids the shell expanding '$' inside values).
getenv() { grep -E "^$1=" .env | head -1 | cut -d= -f2- || true; }

ACME_EMAIL="$(getenv ACME_EMAIL)"
STATUS_DOMAINS="$(getenv STATUS_DOMAINS)"
ADMIN_DOMAIN="$(getenv ADMIN_DOMAIN)"
ADMIN_BASICAUTH_USER="$(getenv ADMIN_BASICAUTH_USER)"
ADMIN_BASICAUTH_HASH="$(< "$HASH_FILE")"

for v in ACME_EMAIL STATUS_DOMAINS ADMIN_DOMAIN ADMIN_BASICAUTH_USER ADMIN_BASICAUTH_HASH; do
	if [[ -z "${!v}" ]]; then
		echo "ERROR: $v is empty (check .env / $HASH_FILE)." >&2
		exit 1
	fi
done

content="$(cat "$TMPL")"
content="${content//@@ACME_EMAIL@@/$ACME_EMAIL}"
content="${content//@@STATUS_DOMAINS@@/$STATUS_DOMAINS}"
content="${content//@@ADMIN_DOMAIN@@/$ADMIN_DOMAIN}"
content="${content//@@ADMIN_BASICAUTH_USER@@/$ADMIN_BASICAUTH_USER}"
content="${content//@@ADMIN_BASICAUTH_HASH@@/$ADMIN_BASICAUTH_HASH}"

printf '%s\n' "$content" > "$OUT"
echo "Rendered $OUT"
