#!/usr/bin/env bash
# 20-sshd.sh — sshd hardening. Idempotent, validates config before applying.
# Preserves: root login (owner may still use it), custom Port.
# Sets: key-only auth, no password auth, no X11/agent forwarding for agent user.
# SAFE GUARD: refuses to run if no authorized_keys exists for root or tyler.
set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONF_DIR="/etc/ssh/sshd_config.d"

echo "=== sshd hardening ==="

# --- safety guard: never cut the branch we sit on ---
check_key() {
    local home="$1"
    [ -f "${home}/.ssh/authorized_keys" ] && grep -q . "${home}/.ssh/authorized_keys"
}
if ! check_key /root && ! check_key /home/tyler; then
    echo "ERROR: no authorized_keys for root or tyler. Install a key first (10-user.sh)." >&2
    exit 1
fi
echo "    key check: ok (root or tyler has authorized_keys)"

# --- drop-in config ---
# CRITICAL: sshd uses FIRST-match semantics, and sshd_config.d files load in
# alphabetical order. Ubuntu ships 50-cloud-init.conf with PasswordAuthentication
# yes — our drop-in must sort BEFORE it (00-...) to win.
SSHD_CONF_DIR="/etc/ssh/sshd_config.d"
DROPIN="${SSHD_CONF_DIR}/00-vps-hardening.conf"
mkdir -p "${SSHD_CONF_DIR}"
cat > "${DROPIN}" <<'EOF'
# Managed by admin-utils. Do not edit by hand.
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PubkeyAuthentication yes
MaxAuthTries 4
LoginGraceTime 20
AllowAgentForwarding no
AllowTcpForwarding yes
X11Forwarding no
ClientAliveInterval 120
ClientAliveCountMax 3
EOF

# Neutralize conflicting "yes" in stock drop-ins (cloud-init etc.)
for f in "${SSHD_CONF_DIR}"/*.conf; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$(basename "${DROPIN}")" ] && continue
    sed -i -E 's/^(PasswordAuthentication[[:space:]]+)yes/\1no/i' "$f" || true
done

# Legacy main config: neutralize conflicting directives if present
sed -i -E 's/^(PasswordAuthentication[[:space:]]+)yes/\1no/i' "${SSHD_CONFIG}" || true

# --- validate BEFORE restart; rollback on failure ---
if ! sshd -t 2>/dev/null; then
    echo "    sshd config invalid — rolling back" >&2
    rm -f "${DROPIN}"
    sshd -t && systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    exit 1
fi

systemctl restart sshd 2>/dev/null || systemctl restart ssh
echo "    sshd restarted with hardened config (${DROPIN})"

# Post-restart guard: verify sshd is alive, rollback if dead
sleep 1
if ! systemctl is-active sshd >/dev/null 2>&1 && ! systemctl is-active ssh >/dev/null 2>&1; then
    echo "    sshd FAILED to start — rolling back!" >&2
    rm -f "${DROPIN}"
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
    exit 1
fi
echo "=== 20-sshd done (VERIFY KEY LOGIN FROM OUTSIDE BEFORE DISCONNECTING!) ==="
