#!/usr/bin/env bash
# 40-fail2ban.sh — brute-force protection for sshd. Idempotent.
set -euo pipefail

if ! command -v fail2ban-client >/dev/null; then
    apt-get update -qq && apt-get install -y -qq fail2ban
fi

echo "=== fail2ban setup ==="

# --- jail config: drop-in only, never touch stock files ---
mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd-hard.local <<'EOF'
# Managed by vps-hardening
[sshd]
enabled  = true
port     = ssh
maxretry = 5
findtime = 10m
bantime  = 1h
bantime.increment = true
bantime.maxtime = 1w
EOF

# Real SSH port (non-standard setups): patch the port= line to match reality
SSH_PORT="$(ss -tln | awk '/ssh/ {print $4}' | grep -oE '[0-9]+$' | head -1 || true)"
if [ -n "${SSH_PORT}" ] && [ "${SSH_PORT}" != "22" ]; then
    sed -i "s/^port.*/port     = ${SSH_PORT}/" /etc/fail2ban/jail.d/sshd-hard.local
    echo "    jail port set to detected SSH port ${SSH_PORT}"
fi

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban
sleep 1
fail2ban-client status sshd | sed 's/^/    /'
echo "=== 40-fail2ban done ==="
