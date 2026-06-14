# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A deployment repo (no application source) for a **single Uptime Kuma instance behind Caddy** that
serves a per-project status page on its own subdomain, with Slack downtime alerts. There is no build
or test suite — the "code" is Docker Compose, a Caddyfile, and Bash operational scripts. Validation,
not unit tests, is the gate (see below).

## Architecture

- **`docker-compose.yml`** — two services on a private `edge` bridge network:
  - `uptime-kuma` (container `kuma`): the app + its SQLite DB in the `kuma-data` volume. **Not**
    published to the host — only Caddy reaches it as `uptime-kuma:3001`.
  - `caddy`: terminates TLS on `:80/:443` (+ `:443/udp` HTTP/3), reverse-proxies every domain to
    Kuma. Certs persist in the `caddy-data` volume.
- **`caddy/Caddyfile.tmpl`** (committed) → **`caddy/Caddyfile`** (generated, gitignored).
  `scripts/render-caddyfile.sh` substitutes `@@PLACEHOLDERS@@` from `.env` + `caddy/admin.hash`.
  - **Why rendered, not Caddy `{$VAR}` + `env_file`:** Docker Compose interpolates env-file *values*,
    which mangles a bcrypt hash's `$` chars before Caddy sees them (verified). Pure-bash
    `${var//pat/repl}` inserts values literally, so the hash survives. **Don't** reintroduce
    `env_file` on the caddy service or `{$VAR}` for the hash.
  - `@@STATUS_DOMAINS@@` is a *space-separated* host list → all proxy to Kuma, which picks the right
    status page by `Host`. Adding a project = append a domain to `STATUS_DOMAINS` in `.env`.
  - `@@ADMIN_DOMAIN@@` is the dashboard host, behind `basic_auth` (Caddy v2 directive name).
  - `reverse_proxy` handles Kuma's WebSocket automatically — do **not** add manual `Upgrade`/
    `Connection` headers.
- **Domains live in two places** that must stay in sync: `STATUS_DOMAINS` in `.env` (so Caddy gets a
  cert + routes it) **and** the status page's *Domain Names* field in the Kuma UI (so Kuma serves
  the right page). Changing one without the other breaks that page.
- **`caddy/Caddyfile` is a bind mount**: if it doesn't exist when `docker compose up` runs, Docker
  creates a *directory* at that path and Caddy fails. Always `make render` (or `make deploy`) first.
- **Slack** is configured at runtime in the Kuma UI (notification + per-monitor attachment), not in
  this repo. The only Slack secret in-repo is `SLACK_WEBHOOK_URL` in `.env`, used by the watchdog.

## Scripts (`scripts/`)

- `render-caddyfile.sh` (`make render`) — generate `caddy/Caddyfile` from the template. Run before
  any validate/up. Reads `.env` via a `getenv` grep (not `source`) and the hash from
  `caddy/admin.hash`. Refuses to run if `caddy/Caddyfile` exists as a directory (the bind-mount
  footgun).
- `set-admin-password.sh` (`make hash`) — prompt (silently) for the admin password and write its
  bcrypt hash to `caddy/admin.hash`. Passes plaintext via `-e PW` (never a host CLI arg) to keep it
  out of shell history / `ps`.
- `bootstrap-server.sh` — one-time server prep (Docker install + UFW incl. 443/udp for HTTP/3). Runs
  **on the server as root**. Idempotent.
- `deploy.sh` (`make deploy`) — render → validate → `compose pull` → `up -d` → **reload Caddy** →
  prune. The reload is essential: a changed bind-mounted Caddyfile does NOT recreate the container,
  so `up -d` alone leaves Caddy serving its old in-memory config (new status domains wouldn't go
  live). `make up`/`make restart` also render first and apply the new config.
- `backup.sh` (`make backup`) — tars `kuma-data` + `caddy-data` via `--volumes-from` to `./backups/`,
  rotates to newest `KEEP` (default 14). Assumes GNU coreutils (Linux host).
- `restore.sh <tarball>` — destructive restore with an EXIT trap that always restarts Kuma, and
  extract-+-verify-before-wipe ordering so a bad tarball can't leave `/app/data` half-deleted.
- `watchdog.sh` — out-of-band check that Kuma is reachable. Alerts Slack only on a **DOWN
  transition**, sends a **RECOVERED** notice, and re-alerts at most once per `RENOTIFY_SECONDS`
  (default 3600) while still down — state persists in `.watchdog.state` (gitignored). Reads config
  from env or `.env` via a `getenv` grep (deliberately **not** `source`). Meant for cron, ideally on
  a different host.

## Validation gate (this repo's "tests")

Before declaring any change done, run and show output for the layers that apply:

```bash
make validate                      # render + docker compose config -q + caddy validate (caddy:2 image)
shellcheck scripts/*.sh            # all scripts must be clean; each starts with `set -euo pipefail`
```

`make validate` needs a populated `.env` (copy from `.env.example`) and a `caddy/admin.hash`
(`make hash PW=…`). It renders the Caddyfile, then runs the real `caddy` adapter inside the `caddy:2`
image against the rendered file, catching bad directives and unset domains.

## Conventions / gotchas

- **Never commit secrets** (all gitignored): `.env` (Slack webhook), `caddy/admin.hash` (bcrypt
  hash), and the rendered `caddy/Caddyfile` (embeds the hash). Only `.env.example`,
  `caddy/admin.hash.example`, and `caddy/Caddyfile.tmpl` are tracked. Don't echo `SLACK_WEBHOOK_URL`.
- Scripts: `set -euo pipefail`, quote expansions, handle exit codes, stay idempotent, no `source`
  of `.env`.
- The compose `name:` is `kumauptime`, so volumes are `kumauptime_kuma-data` etc. Backup/restore use
  `--volumes-from <container>` to sidestep that prefix — keep using container names (`kuma`,
  `caddy`), not raw volume names.
- The Kuma image is pinned to a digest in docker-compose.yml (the `:1` line). Bump deliberately via
  `docker inspect --format '{{index .RepoDigests 0}}' louislam/uptime-kuma:1`. Caddy stays on `:2`
  (TLS security patches via `make deploy`).
- This stack is a single point of failure for both status pages and alerting — preserve the watchdog
  + off-host heartbeat when refactoring; don't remove the out-of-band path.
