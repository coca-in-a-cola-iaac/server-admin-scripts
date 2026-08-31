#!/usr/bin/env bash
# 30-ufw.sh — firewall. Idempotent. Default deny incoming, allow SSH/HTTP/HTTPS.
# EXTRA_PORTS env: space-separated additional ports, e.g. EXTRA_PORTS="8443 2222/tcp"
# SAFE GUARD: current SSH port auto-detected and always allowed.
set -euo pipefail

if ! command -v ufw >/dev/null; then
    apt-get update -qq && apt-get install -y -qq ufw
fi

echo "=== ufw setup ==="

# --- detect SSH port (config or running), never lock ourselves out ---
SSH_PORT="$(ss -tlnp 2>/dev/null | grep sshd | grep -oE ':[0-9]+' | head -1 | tr -d ':' || true)"
[ -n "${SSH_PORT}" ] || SSH_PORT="$(ss -tln | awk '/ssh/ {print $4}' | grep -oE '[0-9]+$' | head -1 || true)"
[ -n "${SSH_PORT}" ] || SSH_PORT=22
echo "    detected SSH port: ${SSH_PORT}"

# --- baseline rules (idempotent by nature) ---
ufw allow "${SSH_PORT}"/tcp comment 'SSH' >/dev/null
ufw allow 80/tcp  comment 'HTTP'  >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
echo "    baseline: ${SSH_PORT}/tcp, 80, 443"

# --- extra ports (stage services etc.) ---
for p in ${EXTRA_PORTS:-}; do
    ufw allow "${p}" comment 'extra (vps-hardening)' >/dev/null
    echo "    extra: ${p}"
done

# --- enable without interactive prompt; ufw refuses if 22 closed, we guard above ---
yes | ufw enable >/dev/null 2>&1 || ufw --force enable >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
systemctl enable ufw >/dev/null 2>&1 || true

echo "    status:"
ufw status verbose | sed 's/^/    /'
echo "=== 30-ufw done ==="
