#!/usr/bin/env bash
# Prompt silently for the admin password and write its bcrypt hash to
# caddy/admin.hash. The plaintext is passed to the container via an env var
# (-e PW), NEVER as a host CLI argument, so it stays out of shell history and
# the host process list.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

read -rsp 'Admin password: ' PW; echo
read -rsp 'Confirm password: ' PW2; echo
[[ -n "$PW" ]]        || { echo "ERROR: empty password." >&2; exit 1; }
[[ "$PW" == "$PW2" ]] || { echo "ERROR: passwords do not match." >&2; exit 1; }

# caddy expands $PW inside the container (escaped here so the host shell does not).
PW="$PW" docker run --rm -e PW caddy:2 sh -c "caddy hash-password --plaintext \"\$PW\"" > caddy/admin.hash
unset PW PW2
echo "Wrote caddy/admin.hash"
