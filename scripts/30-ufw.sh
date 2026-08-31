#!/usr/bin/env bash
# 30-ufw.sh — firewall. Idempotent. Default deny incoming, allow SSH/HTTP/HTTPS.
# EXTRA_PORTS env: space-separated additional ports, e.g. EXTRA_PORTS="8443 2222/tcp"
#
# ANTI-SELF-TRICKERY (pair of 20-sshd.sh):
#   1. SSH port source of truth = sshd -T (effective config), not ss/guessing.
#   2. Rules are added BEFORE `ufw enable`, never after.
#   3. If 20-sshd.sh already wrote /run/admin-utils-ssh-port, that value wins
#      (it was taken at sshd-restart time — the most fresh reading).
#   4. Rule order inside ufw is irrelevant for allow/deny — what matters is
#      that the rule EXISTS before enable. We verify it after enable.
set -euo pipefail

if ! command -v ufw >/dev/null; then
    apt-get update -qq && apt-get install -y -qq ufw
fi

echo "=== ufw setup ==="

# --- SSH port: effective sshd config first, portfile from 20-sshd second ---
SSH_PORT="$(sshd -T 2>/dev/null | grep -iE '^port ' | awk '{print $2}' | head -1 || true)"
if [ -z "${SSH_PORT}" ] && [ -f /run/admin-utils-ssh-port ]; then
    SSH_PORT="$(cat /run/admin-utils-ssh-port)"
    echo "    sshd -T unavailable; using port from 20-sshd: ${SSH_PORT}"
fi
[ -n "${SSH_PORT}" ] || SSH_PORT=22
echo "    detected SSH port: ${SSH_PORT}"

# --- baseline rules BEFORE enable ---
ufw allow "${SSH_PORT}"/tcp comment 'SSH' >/dev/null
ufw allow 80/tcp  comment 'HTTP'  >/dev/null
ufw allow 443/tcp comment 'HTTPS' >/dev/null
echo "    baseline: ${SSH_PORT}/tcp, 80, 443"

# --- extra ports (stage services etc.) ---
for p in ${EXTRA_PORTS:-}; do
    ufw allow "${p}" comment 'extra (vps-hardening)' >/dev/null
    echo "    extra: ${p}"
done

# --- enable without interactive prompt ---
yes | ufw enable >/dev/null 2>&1 || ufw --force enable >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
systemctl enable ufw >/dev/null 2>&1 || true

# --- POST-ENABLE VERIFY: SSH rule must exist, else emergency re-add ---
if ! ufw status | grep -qE "${SSH_PORT}/tcp"; then
    echo "    WARNING: ${SSH_PORT}/tcp rule missing after enable — re-adding!" >&2
    ufw allow "${SSH_PORT}"/tcp comment 'SSH (re-added post-enable)' >/dev/null
fi

# --- final sanity: rule present AND sshd actually listening on it ---
LISTEN_OK=0
if command -v sshd >/dev/null 2>&1; then
    REAL_PORT="$(sshd -T 2>/dev/null | grep -iE '^port ' | awk '{print $2}' | head -1)"
    [ -n "${REAL_PORT}" ] || REAL_PORT="${SSH_PORT}"
    if [ "${REAL_PORT}" != "${SSH_PORT}" ]; then
        echo "    WARNING: sshd effective port (${REAL_PORT}) != ufw rule (${SSH_PORT}) — fixing!" >&2
        ufw allow "${REAL_PORT}"/tcp comment 'SSH (auto-corrected)' >/dev/null
        SSH_PORT="${REAL_PORT}"
    fi
    LISTEN_OK=1
fi

echo "    status:"
ufw status verbose | sed 's/^/    /'
if [ "${LISTEN_OK}" -eq 1 ]; then
    echo "    cross-check: sshd listens on ${SSH_PORT}/tcp, ufw allows it — coherent"
fi
echo "=== 30-ufw done ==="
