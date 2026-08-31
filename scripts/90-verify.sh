#!/usr/bin/env bash
# 90-verify.sh — final gate: run ALL checks; non-zero exit if anything critical fails.
# Usage: bash 90-verify.sh   (after 10..50)
set -uo pipefail

PASS=0; FAIL=0
check() { # check <name> <cmd...>
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo "  OK   ${name}"; PASS=$((PASS+1))
    else
        echo "  FAIL ${name}"; FAIL=$((FAIL+1))
    fi
}

echo "=== verification ==="
check "user tyler exists"            id tyler
check "tyler in sudo group"          sh -c 'id -nG tyler | grep -qw sudo'
check "sudoers file valid"           visudo -c
check "tyler passwordless sudo"      sudo -u tyler sudo -n true
check "tyler authorized_keys"        sh -c 'test -s /home/tyler/.ssh/authorized_keys'
check "sshd config valid"            sshd -t
check "sshd running"                 systemctl is-active ssh
check "password auth disabled"       sh -c 'sshd -T 2>/dev/null | grep -qi "^passwordauthentication no"'
check "pubkey auth enabled"          sh -c 'sshd -T 2>/dev/null | grep -qi "^pubkeyauthentication yes"'
check "ufw active"                   sh -c 'ufw status | grep -q "Status: active"'
check "ufw default deny incoming"    sh -c 'ufw status verbose | grep -qi "deny (incoming)"'
check "fail2ban running"             systemctl is-active fail2ban
check "fail2ban sshd jail enabled"   sh -c 'fail2ban-client status sshd >/dev/null 2>&1'
check "unattended-upgrades"          sh -c 'test -f /etc/apt/apt.conf.d/20auto-upgrades'
check "journald cap"                 sh -c 'test -f /etc/systemd/journald.conf.d/size-cap.conf'

echo "=== result: ${PASS} ok, ${FAIL} fail ==="
if [ "${FAIL}" -eq 0 ]; then
    # Connection card for Tyler: copy-paste line with all access details
    TYLER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [ -n "${TYLER_IP}" ] || TYLER_IP=$(ip -4 addr show scope global 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2)
    SSH_PORT="$(ss -tln 2>/dev/null | awk '/sshd|:22 / {print $4}' | grep -oE '[0-9]+$' | head -1)"
    [ -n "${SSH_PORT}" ] || SSH_PORT=22
    OS="$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)"
    RAM="$(free -m 2>/dev/null | awk '/Mem:/ {print $2"MB"}')"
    DISK="$(df -h / 2>/dev/null | awk 'NR==2 {print $4" free"}')"
    echo ""
    echo "=========================================="
    echo "ALL GREEN — server ready for Tyler"
    echo "------------------------------------------"
    echo "COPY THIS TO TYLER:"
    echo "IP: ${TYLER_IP:-<public-ip>}"
    echo "SSH порт: ${SSH_PORT}"
    echo "Подключайся: ssh tyler@${TYLER_IP:-<ip>} -p ${SSH_PORT}"
    echo "------------------------------------------"
    echo "(${OS:-?}, ${RAM:-?} RAM, / ${DISK:-?})"
    echo "=========================================="
else
    echo "RED — fix failures above"
fi
exit "${FAIL}"
