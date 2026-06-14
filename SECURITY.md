# Security Policy

`kumauptime` is a **deployment-only** repo: Docker Compose, a Caddyfile template, and
hardened Bash scripts that run a single Uptime Kuma instance behind Caddy. It ships no
application source — the bundled images (`louislam/uptime-kuma`, `caddy:2`) carry their
own upstream security tracks. This policy covers the config, scripts, and defaults in
**this** repo; vulnerabilities in Uptime Kuma or Caddy themselves should go upstream.

## Reporting a vulnerability

**Report privately — do not open a public issue, PR, or discussion for a vulnerability.**

Use **GitHub's private vulnerability reporting** for this repository:

> **Security** tab → **Report a vulnerability** (GitHub Security Advisories)
> <https://github.com/zakrian07/kumauptime/security/advisories/new>

This opens a private advisory visible only to you and the maintainer. If private
advisories are unavailable to you, open a minimal public issue that says only "security
report — please enable a private channel" with **no** exploit details, and wait to be
contacted. Reach the maintainer via the GitHub profile linked from the repo.

Please include, where you can:

- affected file(s) / script / config (e.g. `scripts/render-caddyfile.sh`, `docker-compose.yml`, `caddy/Caddyfile.tmpl`)
- the impact (what an attacker gains) and the conditions / config needed to trigger it
- reproduction steps or a proof of concept
- any suggested fix

**Do not** include real secrets in a report — redact `SLACK_WEBHOOK_URL`, the
`caddy/admin.hash` bcrypt hash, ACME account data, and any live domains/credentials.

### What to expect

- Acknowledgement of your report, typically within a few days.
- An assessment and, for confirmed issues, a fix on a private branch with a coordinated
  public disclosure once a remediation is available.
- Credit in the advisory if you'd like it.

This is a small, single-maintainer MIT project run on a best-effort basis; there is no
paid bug-bounty.

## Supported versions

There are no tagged releases. **The default branch is the only supported version** — fixes
land there. If you deployed from an older checkout, pull the latest `main`, re-run
`make validate`, then `make deploy`.

For the images this stack runs:

- **Uptime Kuma** — the tag `louislam/uptime-kuma:1` tracks the 1.x line. **Pin a digest
  in production** (`louislam/uptime-kuma@sha256:…`) and bump it deliberately so you control
  when you take an upstream change. `make pull` + `make deploy` rolls a new image.
- **Caddy** — `caddy:2`; pull regularly for upstream TLS/HTTP fixes.

## Security posture & hardening

What this repo does to reduce its attack surface (see `README.md` and `CLAUDE.md` for the
why behind each):

- **Secrets are gitignored, never committed.** `.env` (holds `SLACK_WEBHOOK_URL`),
  `caddy/admin.hash` (the admin **bcrypt** hash), and the rendered `caddy/Caddyfile` (it
  embeds the hash) are all in `.gitignore`. Only `.env.example`, `caddy/admin.hash.example`,
  and `caddy/Caddyfile.tmpl` are tracked. The admin password is set via `make hash`, which
  prompts silently and passes the plaintext to the hasher out of band (not as a CLI arg), so
  it never lands in shell history or `ps`.
- **Kuma is never exposed to the host.** In `docker-compose.yml` the app is `expose`-only on
  the private `edge` bridge network and reached solely as `uptime-kuma:3001` by Caddy. Only
  Caddy binds host ports (`80`, `443`, `443/udp`).
- **TLS everywhere, automatically.** Caddy issues and renews a per-domain Let's Encrypt
  certificate and serves HTTPS (HTTP/3 ready). The `(common)` snippet adds HSTS,
  `X-Content-Type-Options: nosniff`, a `Referrer-Policy`, and strips the `Server` header on
  every site.
- **Admin dashboard behind Basic Auth.** The admin UI lives on its own `ADMIN_DOMAIN`,
  fronted by Caddy `basic_auth` as defense-in-depth **on top of** Kuma's own login. Public
  status-page domains do not expose the dashboard.
- **`no-new-privileges` on both containers**, `restart: unless-stopped`, and bounded
  `json-file` logging (size/rotation capped) so a noisy or compromised process can't exhaust
  disk via logs.
- **Validation is the gate.** `make validate` renders the Caddyfile then runs
  `docker compose config` and `caddy validate` (via the `caddy:2` image); `shellcheck
  scripts/*.sh` must be clean and every script runs `set -euo pipefail`. Run both before any
  deploy.
- **Untrusted input stays at the boundary.** Scripts read `.env` via a `getenv` grep rather
  than `source`-ing it, so file contents can't execute as shell.
- **Safe backups/restore.** `make backup` captures `kuma-data` (the SQLite DB) **and**
  `caddy-data` (ACME certs — also avoids Let's Encrypt rate limits on rebuild);
  `scripts/restore.sh` extracts-and-verifies before wiping and always restarts Kuma via an
  exit trap.

### Known caveats — your responsibility to mitigate

- **Single point of failure (SPOF).** This is **one** instance on **one** host: if the box
  dies, every status page *and* the alerting go dark together. **Host it off the
  infrastructure it monitors** so a shared outage can't take down both.
- **Keep the out-of-band watchdog + heartbeat.** Kuma cannot alert that Kuma is down, so the
  SPOF safety net is `scripts/watchdog.sh` on cron — **ideally on a different host** — plus an
  optional off-host dead-man's switch via `HEARTBEAT_PING_URL` (e.g. healthchecks.io). Do not
  remove this out-of-band path when modifying the stack.
- **You operate the host.** This repo hardens the container stack, not the server. Keep the
  OS and Docker patched, restrict SSH, and keep the firewall to `22/80/443` (+ `443/udp`) as
  `scripts/bootstrap-server.sh` sets up.
- **Protect `.env`, `caddy/admin.hash`, and `caddy-data` at rest** on the host (restrictive
  file permissions, encrypted/access-controlled backups) — they hold the Slack webhook, the
  admin hash, and your TLS private keys.
