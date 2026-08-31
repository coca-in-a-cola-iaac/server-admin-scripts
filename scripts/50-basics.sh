#!/usr/bin/env bash
# 50-basics.sh — system basics: unattended upgrades, time, limits, journald caps, cleanup.
# Idempotent.
set -euo pipefail

echo "=== basics ==="

# --- auto security updates ---
if [ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
    apt-get update -qq && apt-get install -y -qq unattended-upgrades
    echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo "    unattended-upgrades enabled"
else
    echo "    unattended-upgrades already configured"
fi

# --- timezone: Ekaterinburg (owner) ---
timedatectl set-timezone Asia/Yekaterinburg 2>/dev/null || true

# --- journald: cap disk usage (95% disk incident lesson) ---
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/size-cap.conf <<'EOF'
# Managed by vps-hardening
[Journal]
SystemMaxUse=200M
SystemKeepFree=500M
MaxRetentionSec=2week
EOF
systemctl restart systemd-journald 2>/dev/null || true
echo "    journald capped at 200M"

# --- swappiness for small VPS ---
sysctl -qw vm.swappiness=20
echo "vm.swappiness=20" > /etc/sysctl.d/90-tyler.conf

# --- daily apt autoclean ---
cat > /etc/cron.d/vps-hardening-clean <<'EOF'
# Managed by vps-hardening: keep /var/cache/apt lean
15 4 * * * root apt-get -qq autoclean && apt-get -qq autoremove --purge -y >/dev/null 2>&1
EOF

echo "=== 50-basics done ==="
