#!/usr/bin/env bash
# 20-sshd.sh — sshd hardening. Idempotent, validates config before applying.
#
# POLICY (anti-lockout):
#   - Password auth stays ENABLED for owner accounts (via Match block).
#     Everyone else: key-only.
#   - Owner accounts are configurable: OWNER_USERS="root alice"
#   - SSH Port is NEVER changed by this script (we only read it).
#   - If 10-user.sh was skipped (no agent user), script bails before touching sshd.
#
# ANTI-SELF-TRICKERY (shared with 30-ufw.sh via /run/admin-utils-ssh-port):
#   The actual listening SSH port is detected from sshd -T (effective config),
#   and ALWAYS: (1) echoed in a status file for 30-ufw.sh to consume,
#   (2) ufw rule is added for it RIGHT HERE, before any firewall can run.
#   So no matter the order of scripts or manual ufw changes, the real SSH
#   port is never left unreachable.
set -euo pipefail

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONF_DIR="/etc/ssh/sshd_config.d"
DROPIN="${SSHD_CONF_DIR}/00-vps-hardening.conf"
PORTFILE="/run/admin-utils-ssh-port"
OWNER_USERS="${OWNER_USERS:-root}"

echo "=== sshd hardening ==="

# --- guard 1: agent key must exist, or we refuse to touch sshd ---
if ! grep -q . /home/tyler/.ssh/authorized_keys 2>/dev/null; then
    echo "ERROR: /home/tyler/.ssh/authorized_keys missing/empty. Run 10-user.sh first." >&2
    exit 1
fi
echo "    guard: tyler authorized_keys present"

# --- guard 2: every owner user must have SOME way in (key or password currently allowed) ---
for u in ${OWNER_USERS}; do
    h=$(getent passwd "$u" | cut -d: -f6)
    h="${h:-/root}"
    if [ -s "${h}/.ssh/authorized_keys" ]; then
        echo "    guard: ${u} has authorized_keys (key path ok)"
    else
        echo "    guard: ${u} has NO key — password auth will be KEPT for owner users"
    fi
done

# --- detect EFFECTIVE ssh port (before any changes; read-only) ---
# sshd -T shows the real effective value incl. sshd_config.d includes.
CUR_PORT="$(sshd -T 2>/dev/null | grep -iE '^port ' | awk '{print $2}' | head -1)"
[ -n "${CUR_PORT}" ] || CUR_PORT=22
echo "    current effective sshd port: ${CUR_PORT} (script NEVER changes it)"

# --- drop-in config ---
# sshd uses FIRST-match semantics; sshd_config.d loads alphabetically, so our
# drop-in is 00- to beat cloud-init's 50-cloud-init.conf (PasswordAuthentication yes).
mkdir -p "${SSHD_CONF_DIR}"
{
cat <<EOF
# Managed by admin-utils. Do not edit by hand.
# Global: key-only. Owner accounts re-enable password auth in Match block below.
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
# Owner escape hatch: password login (PAM) preserved for humans, key OR password.
# Match resets all boolean-ish options, so re-state what matters inside the block.
for u in ${OWNER_USERS}; do
    echo "Match User ${u}"
    echo "    PasswordAuthentication yes"
    echo "    KbdInteractiveAuthentication yes"
    if [ "$u" = "root" ]; then
        echo "    PermitRootLogin yes"
    fi
done
} > "${DROPIN}"

# Neutralize conflicting "yes" in stock drop-ins (cloud-init etc.)
for f in "${SSHD_CONF_DIR}"/*.conf; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = "$(basename "${DROPIN}")" ] && continue
    sed -i -E 's/^(PasswordAuthentication[[:space:]]+)yes/\1no/i' "$f" || true
done

# --- validate BEFORE restart; rollback on failure ---
if ! sshd -t 2>/dev/null; then
    echo "    sshd config invalid — rolling back" >&2
    rm -f "${DROPIN}"
    sshd -t && systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    exit 1
fi

systemctl restart sshd 2>/dev/null || systemctl restart ssh
echo "    sshd restarted with hardened config (${DROPIN})"

# --- post-restart guard: sshd alive + effective values sane ---
sleep 1
if ! systemctl is-active sshd >/dev/null 2>&1 && ! systemctl is-active ssh >/dev/null 2>&1; then
    echo "    sshd FAILED to start — rolling back!" >&2
    rm -f "${DROPIN}"
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
    exit 1
fi

# --- ANTI-TRICKERY: publish the real port AND open it in ufw right now ---
# (ufw may not even be installed yet — guard against that; if ufw inactive,
#  30-ufw.sh will re-add the rule when enabling. Writing the rule twice is safe.)
if command -v ufw >/dev/null 2>&1; then
    ufw allow "${CUR_PORT}"/tcp comment 'SSH (auto, from 20-sshd)' >/dev/null 2>&1 || true
    echo "    ufw: ensured ${CUR_PORT}/tcp allowed"
fi
echo "${CUR_PORT}" > "${PORTFILE}"
chmod 644 "${PORTFILE}" 2>/dev/null || true

echo "    effective config (no Match context):"
sshd -T 2>/dev/null | grep -E "^(passwordauthentication|pubkeyauthentication|permitrootlogin|port )" | sed 's/^/        /'
for u in ${OWNER_USERS}; do
    echo "    effective config (owner user ${u}):"
    sshd -T -C user=${u},host=x,addr=1.2.3.4 2>/dev/null | grep -E "^(passwordauthentication|permitrootlogin)" | sed 's/^/        /' || true
done
echo "=== 20-sshd done (VERIFY KEY LOGIN FROM OUTSIDE BEFORE DISCONNECTING!) ==="
