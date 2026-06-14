<!--
kumauptime is a deployment-only repo. There's no app source or unit suite —
validation is the gate. Keep PRs to one logical change and tick the boxes below.
-->

## What & why

<!-- One or two sentences: what this changes and why. -->

## Validation

- [ ] `shellcheck scripts/*.sh` is clean
- [ ] `make validate` passes (renders `caddy/Caddyfile`, then `docker compose config` + `caddy validate`)
- [ ] No secrets committed — `.env`, `caddy/admin.hash`, and the rendered `caddy/Caddyfile` stay gitignored (only `*.example` / `*.tmpl` are tracked)
- [ ] Scripts still start with `set -euo pipefail` (quoted expansions, no `source` of `.env`, idempotent)
- [ ] Docs updated (`README.md` / `CLAUDE.md`) if behavior, make targets, or env vars changed

## Notes

<!-- Anything reviewers should know: new STATUS_DOMAINS, Caddyfile.tmpl placeholders, image pins, etc. -->
