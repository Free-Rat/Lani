#!/usr/bin/env bash
# Health-check a booted Lani services container. Runs on the host, not inside.
#
#   health.sh <machine> [timeout_seconds] [interface]
#
# Prints the container's IPv4 on stdout, exits 0 when every check passes, 1 on the first
# timeout. What to check comes from /etc/lani-health-manifest.json, which the platform
# generates — so adding a service never means editing this file.
set -euo pipefail

M="${1:-lani-services-test}"
TIMEOUT="${2:-180}"
IFACE="${3:-host0}"

log() { echo "[health $M] $*" >&2; }

# Output to stderr so it cannot pollute the IP we print on stdout.
inside() {
  systemd-run --machine="$M" --quiet --pipe --wait --collect \
    /run/current-system/sw/bin/bash -lc "$1" >&2 2>&1
}

inside_cap() {
  systemd-run --machine="$M" --quiet --pipe --wait --collect \
    /run/current-system/sw/bin/bash -lc "$1" 2>/dev/null
}

deadline=$((SECONDS + TIMEOUT))

# wait_for <description> <command...> — a real command, not a string to eval.
wait_for() {
  local desc="$1"
  shift
  until "$@"; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      log "TIMEOUT waiting for: $desc"
      return 1
    fi
    sleep 3
  done
  log "ok: $desc"
}

machine_running() { machinectl status "$M" >/dev/null 2>&1; }
port_listening() { inside "ss -tln | grep -q ':$1 '"; }
vhost_responds() { inside "curl -fsSo /dev/null -H 'Host: $1.local' http://localhost/"; }

wait_for "machine running" machine_running

log "reading health manifest"
manifest="$(inside_cap 'cat /etc/lani-health-manifest.json 2>/dev/null' || true)"
if [ -z "$manifest" ]; then
  log "FAIL: no /etc/lani-health-manifest.json in the container"
  log "the platform module did not activate, so there is nothing to verify"
  exit 1
fi

# On stdin, not interpolated into the program text.
services="$(
  printf '%s' "$manifest" | python3 -c '
import json, sys
manifest = json.load(sys.stdin)
for name, svc in manifest.get("services", {}).items():
    print("\t".join([name, str(svc["port"]), svc["subdomain"]]))
'
)"

if [ -z "$services" ]; then
  log "FAIL: manifest declares no services"
  exit 1
fi

log "manifest lists $(printf '%s\n' "$services" | wc -l | tr -d ' ') service(s)"

# Process substitution, not a pipe: a `while read` on the right of a pipe runs in a
# subshell, so a failure inside could only exit the subshell. That is how this check used
# to pass unconditionally.
while IFS=$'\t' read -r name port subdomain; do
  [ -n "$name" ] || continue
  wait_for "$name listening on $port" port_listening "$port"
  wait_for "$name answering as $subdomain.local" vhost_responds "$subdomain"
done < <(printf '%s\n' "$services")

ip="$(inside_cap "ip -4 -o addr show $IFACE | awk '{print \$4}' | cut -d/ -f1 | head -n1" || true)"
ip="$(printf '%s' "$ip" | tr -d '[:space:]')"
log "all checks green; ip=${ip:-unknown}"
printf '%s\n' "$ip"
