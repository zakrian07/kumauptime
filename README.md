# kumauptime — multi-tenant status pages + Slack alerts on one Uptime Kuma instance

> Self-hosted **status pages for many projects from a single [Uptime Kuma](https://github.com/louislam/uptime-kuma) instance** — each on its own subdomain (`status.yourproject.com`) — with automatic HTTPS via **Caddy** and **Slack downtime alerts**, including for the third-party REST APIs you depend on. A production-ready **Docker Compose** stack.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](docker-compose.yml)
[![Caddy auto-HTTPS](https://img.shields.io/badge/Caddy-auto--HTTPS-1F88C0?logo=caddy&logoColor=white)](caddy/Caddyfile.tmpl)
[![Uptime Kuma](https://img.shields.io/badge/Uptime%20Kuma-monitoring-5CDD8B)](https://github.com/louislam/uptime-kuma)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

**kumauptime** runs **one** Uptime Kuma container and publishes a **separate, branded status page per
project/domain** — `status.tokscript.com`, `status.tokdownload.com`, … — instead of spinning up an
instance per site. Caddy handles per-domain TLS certificates automatically; Slack notifies you the
moment any monitored website, service, or REST API goes **down** (and when it **recovers**).
Everything is reproducible from `docker-compose.yml` plus a few hardened Bash scripts.

```
                         ┌── status.tokscript.com ──┐
   DNS (A records)  ───► │   Caddy (TLS, :80/:443)  │ ──► uptime-kuma:3001  (one instance)
                         └── status.tokdownload.com ┘            │
                              kuma-admin.<you>  (Basic Auth)      └── many monitors, many status pages
                                                                       └── Slack notification → #alerts
```

## Features

- 🟢 **One instance, many status pages** — a dedicated public status page per project, each on its
  own (sub)domain, from a single Uptime Kuma container.
- 🔒 **Automatic HTTPS** for every domain via Caddy + Let's Encrypt (HTTP/3 ready) — no manual certs.
- 🔔 **Slack alerts** on down/up for any HTTP / keyword / JSON-query / TCP / ping monitor — including
  **third-party REST API** health.
- 🧱 **Reproducible Docker Compose** stack; Kuma is never exposed to the host (reached only via Caddy).
- 🛡️ **Hardened defaults** — Basic-Auth admin host, security headers, `no-new-privileges`, secrets
  kept out of git, UFW firewall bootstrap.
- 💾 **Backups + safe restore** of Kuma data and Caddy certs (verify-before-wipe, auto-restart).
- 🐶 **Watch-the-watcher** — an out-of-band watchdog + optional off-host dead-man's-switch alerts you
  if Kuma itself dies (transition-based, no alert spam).
- 🧩 **Add a project in one line** — append a domain to `STATUS_DOMAINS`, then `make deploy`.

## Why one instance works

- **Multiple status pages from a single instance** (Uptime Kuma ≥ 1.13). Create one status page
  per project and put that project's domain in the page's **Domain Names** field; Kuma serves the
  right page by `Host` header.
- **Caddy** auto-issues and renews a Let's Encrypt cert for every domain and proxies all of them to
  the one Kuma container (it transparently handles Kuma's WebSocket connection).
- **Slack**: one notification (or one per project channel) attached to monitors fires on down/up.
- **Third-party REST API**: an HTTP(s) monitor (use the *Keyword* or *JSON query* type to assert a
  status code or response field) with the same Slack notification attached.

## Prerequisites

- A small Linux VPS (1–2 GB RAM is plenty). **Host it off the infra it monitors** so a shared
  outage doesn't take down both your services and the thing meant to alert you.
- DNS control for each project domain.
- A Slack incoming-webhook URL (api.slack.com → your app → Incoming Webhooks).

## Quick start

1. **Server prep (one time, on the box):**
   ```bash
   sudo bash scripts/bootstrap-server.sh   # installs Docker + opens 22/80/443 (+ 443/udp for HTTP/3)
   ```
2. **DNS:** for every project add `status.<project>.com` → A record to the server IP. Add one for
   the admin host too (e.g. `kuma-admin.<your-domain>`).
3. **Configure:**
   ```bash
   cp .env.example .env
   # edit .env: ACME_EMAIL, STATUS_DOMAINS (space-separated), ADMIN_DOMAIN, ADMIN_BASICAUTH_USER
   make hash                                 # prompts for the password; writes caddy/admin.hash
   ```
   The admin password hash is kept in `caddy/admin.hash`, **not** `.env` — a bcrypt hash's
   `$` characters get mangled by Docker Compose interpolation, so the Caddyfile is rendered from
   `caddy/Caddyfile.tmpl` with the hash inserted literally.
4. **Validate + launch:**
   ```bash
   make validate     # render Caddyfile + check compose + Caddyfile before touching anything
   make deploy       # render + validate + pull + up -d + reload Caddy
   ```
5. **In the Kuma UI** (`https://kuma-admin.<you>`, create the admin account on first load):
   - Add a **Slack** notification → paste the webhook → *Send Test Notification* → set as default.
   - Add **monitors** per project (HTTP / keyword / JSON-query / TCP / ping), incl. one for each
     third-party REST API. Group them by project.
   - Create one **Status Page** per project; in **Domain Names** add the matching
     `status.<project>.com`; add that project's monitor group.
6. **Watchdog (recommended):** add a cron entry — ideally on a *different* host — so you're alerted
   if Kuma itself goes down:
   ```bash
   */2 * * * * /path/to/kumauptime/scripts/watchdog.sh >> /var/log/kuma-watchdog.log 2>&1
   ```

## Operations

| Command | What it does |
|---|---|
| `make render` | Generate `caddy/Caddyfile` from the template + `.env` + `caddy/admin.hash` |
| `make validate` | Render, then lint compose + Caddyfile |
| `make deploy` | Render, validate, pull images, `up -d`, reload Caddy, prune |
| `make logs` / `make ps` | Tail logs / show status |
| `make backup` | Tar Kuma data + Caddy certs to `./backups/` (keeps newest `KEEP=14`) |
| `scripts/restore.sh <tarball>` | Restore Kuma data from a backup (destructive, prompts) |
| `make hash` | Prompt for the admin password; write its bcrypt hash to `caddy/admin.hash` |

Add `make backup` to daily cron. Adding a status domain later = append it to `STATUS_DOMAINS` in
`.env`, `make deploy` (re-renders + reloads Caddy), then add the same domain in the Kuma status page
settings.

## FAQ

**Can Uptime Kuma host multiple status pages?** Yes — since v1.13 a single instance serves unlimited
status pages. kumauptime maps each to its own domain through Caddy.

**How do I use one Uptime Kuma for multiple domains?** Point each `status.<project>.com` DNS record at
the server, list them in `STATUS_DOMAINS`, and add each to its Status Page's *Domain Names* field.
Caddy issues a TLS certificate per domain automatically.

**How do I get Slack alerts from Uptime Kuma?** Add a Slack incoming-webhook notification in the UI
and attach it to your monitors. kumauptime also ships an out-of-band watchdog that Slacks you if Kuma
itself goes down — and sends a recovery notice when it's back.

**Can I monitor a third-party REST API?** Yes — use an HTTP(s) monitor (Keyword or JSON-query type)
against the API or its health endpoint, with the Slack notification attached.

**Is it production-ready?** It ships hardened defaults, backups/restore, and a watchdog. The one
caveat: a single instance is a single point of failure — host it off the infra it monitors and keep
the off-host heartbeat enabled.

## Notes & hardening

- **Secrets are gitignored**: `.env` (Slack webhook) and `caddy/admin.hash` (admin bcrypt hash).
  The rendered `caddy/Caddyfile` is also gitignored since it embeds the hash. Never commit them.
- **Always go through `make`** (`make deploy` / `make up`), never a bare `docker compose up -d`:
  the targets render the Caddyfile first and reload Caddy after. Running compose directly before
  rendering makes Docker create a *directory* at `caddy/Caddyfile` and Caddy crash-loops.
- **Pin the image** in prod: replace `louislam/uptime-kuma:1` with a digest
  (`louislam/uptime-kuma@sha256:…`) and bump deliberately.
- **Single point of failure:** if this host dies, all status pages *and* alerting go dark. The
  watchdog + an off-host `HEARTBEAT_PING_URL` (e.g. healthchecks.io) is the out-of-band safety net.
- **Back up `caddy-data`** too (certs) — `make backup` does; avoids Let's Encrypt rate limits on
  rebuild.

See [CLAUDE.md](CLAUDE.md) for architecture details aimed at future code assistants.

## Contributing

Issues and pull requests are welcome. Before submitting, run `shellcheck scripts/*.sh` and
`make validate` (both must be clean).

## License

[MIT](LICENSE) © Umer Singhera

---

<sub>Topics: uptime-kuma · status-page · self-hosted · docker · docker-compose · caddy · monitoring ·
slack-alerts · devops · sre · uptime-monitoring · reverse-proxy. &nbsp; Keywords: uptime kuma multiple
status pages, one Uptime Kuma instance multiple domains, self-hosted status page per domain, Docker
Compose uptime monitoring, Caddy automatic HTTPS reverse proxy, Slack uptime/downtime alerts, monitor
multiple websites from one instance, third-party REST API monitoring, multi-tenant status page.</sub>
