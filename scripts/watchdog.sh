#!/usr/bin/env bash
# Out-of-band watchdog: confirms Uptime Kuma is reachable over its public URL.
# Alerts Slack on a DOWN transition (not every poll), sends a RECOVERED notice when
# it comes back, and re-alerts at most once per $RENOTIFY_SECONDS while still down.
# On a healthy run it optionally pings a remote dead-man's switch.
#
# Run from cron. IDEALLY on a DIFFERENT host than Kuma so a full-host/network outage
# is still caught. On the same host it only catches container/app crashes.
#   */2 * * * * /path/to/kumauptime/scripts/watchdog.sh >> /var/log/kuma-watchdog.log 2>&1
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Read config from the environment, falling back to keys in .env (no `source`, so a
# malformed .env can't execute arbitrary code and shellcheck stays clean).
getenv() { grep -E "^$1=" .env 2>/dev/null | head -1 | cut -d= -f2- || true; }
KUMA_HEALTH_URL="${KUMA_HEALTH_URL:-$(getenv KUMA_HEALTH_URL)}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-$(getenv SLACK_WEBHOOK_URL)}"
HEARTBEAT_PING_URL="${HEARTBEAT_PING_URL:-$(getenv HEARTBEAT_PING_URL)}"
STATE_FILE="${STATE_FILE:-$PWD/.watchdog.state}"
RENOTIFY_SECONDS="${RENOTIFY_SECONDS:-3600}"

if [[ -z "$KUMA_HEALTH_URL" ]]; then
	echo "ERROR: KUMA_HEALTH_URL not set (env or .env)." >&2
	exit 2
fi

# Previous state: "UP|0" or "DOWN|<epoch-of-last-alert>".
prev_status="UP"; last_alert=0
if [[ -f "$STATE_FILE" ]]; then
	IFS='|' read -r prev_status last_alert < "$STATE_FILE" || true
	prev_status="${prev_status:-UP}"; last_alert="${last_alert:-0}"
fi
now="$(date +%s)"

post_slack() {
	[[ -n "$SLACK_WEBHOOK_URL" ]] || return 0
	local payload
	payload="$(printf '{"text":"%s"}' "$1")"
	# Never log the webhook URL or response body.
	curl -fsS --max-time 15 -X POST -H 'Content-Type: application/json' \
		-d "$payload" "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || echo "WARN: Slack POST failed" >&2
}
write_state() { printf '%s|%s\n' "$1" "$2" > "$STATE_FILE"; }

# 200/302 = page served; 401 = admin Basic Auth challenge — all mean Kuma is up.
code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 15 "$KUMA_HEALTH_URL" 2>/dev/null || true)"

if [[ "$code" =~ ^(200|302|401)$ ]]; then
	echo "OK: Kuma reachable (HTTP $code) at $KUMA_HEALTH_URL"
	if [[ "$prev_status" == "DOWN" ]]; then
		post_slack ":white_check_mark: Uptime Kuma watchdog: instance RECOVERED (HTTP $code) at $KUMA_HEALTH_URL"
	fi
	write_state "UP" 0
	if [[ -n "$HEARTBEAT_PING_URL" ]]; then
		curl -fsS --max-time 15 "$HEARTBEAT_PING_URL" >/dev/null 2>&1 || echo "WARN: heartbeat ping failed" >&2
	fi
	exit 0
fi

echo "DOWN: Kuma not reachable (HTTP ${code:-none}) at $KUMA_HEALTH_URL" >&2
if [[ "$prev_status" != "DOWN" ]] || (( now - last_alert >= RENOTIFY_SECONDS )); then
	post_slack ":rotating_light: Uptime Kuma watchdog: instance UNREACHABLE (HTTP ${code:-none}) at $KUMA_HEALTH_URL"
	write_state "DOWN" "$now"
else
	write_state "DOWN" "$last_alert"
fi
exit 1
