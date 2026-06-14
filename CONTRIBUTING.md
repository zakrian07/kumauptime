# Contributing

Thanks for helping improve **kumauptime**. This is a deployment-only repo (no application
source) — Docker Compose, a Caddyfile template, and hardened Bash scripts. Validation, not a
unit-test suite, is the gate. Keep changes small, scoped, and validated.

## Local setup

You need Docker (with the Compose plugin) and `shellcheck`. The validation steps run the real
`caddy:2` image, so Docker must be able to pull it.

```bash
cp .env.example .env          # fill in ACME_EMAIL, STATUS_DOMAINS, ADMIN_DOMAIN, ADMIN_BASICAUTH_USER
make hash                     # prompts for the admin password; writes caddy/admin.hash
```

`make validate` needs both a populated `.env` and a `caddy/admin.hash` before it can render the
Caddyfile. For setup values you don't have locally, any syntactically valid placeholder is fine —
you're checking that config renders and parses, not deploying.

## Validation gate (must be clean before you open a PR)

Run both, and paste the output in your PR if a reviewer asks:

```bash
shellcheck scripts/*.sh       # all scripts clean; each starts with `set -euo pipefail`
make validate                 # render Caddyfile → docker compose config -q → caddy validate
```

`make validate` renders `caddy/Caddyfile` from `caddy/Caddyfile.tmpl` using `.env` +
`caddy/admin.hash`, then checks `docker-compose.yml` and runs the Caddy adapter against the rendered
file inside the `caddy:2` image. Both commands must exit clean — no warnings suppressed, no checks
disabled. Don't silence shellcheck with inline `# shellcheck disable=…` to get green; fix the root
cause or explain it in the PR.

## Conventions you must keep

- **Secrets are gitignored — never commit them.** `.env` (Slack webhook), `caddy/admin.hash`
  (bcrypt hash), and the rendered `caddy/Caddyfile` (it embeds the hash). Only `.env.example`,
  `caddy/admin.hash.example`, and `caddy/Caddyfile.tmpl` are tracked. Scan your staged diff before
  committing; if a secret-shaped string is in it, stop.
- **Caddyfile is rendered, not edited.** Change `caddy/Caddyfile.tmpl`, never the generated
  `caddy/Caddyfile`. The render step exists because Docker Compose interpolation mangles a bcrypt
  hash's `$`; don't reintroduce `env_file` on the caddy service or `{$VAR}` for the hash.
- **Scripts** use `set -euo pipefail`, quote expansions, stay idempotent, and read `.env` via a
  `getenv` grep — not `source`. Match the existing style.
- Don't `echo`/log `SLACK_WEBHOOK_URL` or the admin password/hash.

## Commit / PR etiquette

- One logical change per commit; clear, imperative message. Don't bundle unrelated edits, and don't
  add signature/co-author trailers.
- PRs: describe what changed and why, and confirm `shellcheck scripts/*.sh` and `make validate` are
  both clean. Update `README.md` / `CLAUDE.md` when you change behavior, make targets, or scripts.
- Don't commit generated or local files (`caddy/Caddyfile`, `backups/`, `.watchdog.state`) — they're
  gitignored for a reason.

## Reporting a vulnerability

Please don't open a public issue for security problems. Use a
[private security advisory](https://github.com/zakrian07/kumauptime/security/advisories/new) on the
repo. For non-security bugs and features, open a regular
[issue](https://github.com/zakrian07/kumauptime/issues).
