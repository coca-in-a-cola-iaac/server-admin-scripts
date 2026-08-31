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
check "password auth disabled"       sh -c 'sshd -T | grep -qi "^passwordauthentication no"'
check "pubkey auth enabled"          sh -c 'sshd -T | grep -qi "^pubkeyauthentication yes"'
check "ufw active"                   sh -c 'ufw status | grep -q "Status: active"'
check "ufw default deny incoming"    sh -c 'ufw status verbose | grep -qi "deny (incoming)"'
check "fail2ban running"             systemctl is-active fail2ban
check "fail2ban sshd jail"           sh -c 'fail2ban-client status sshd | grep -q "Jail settings"'
check "unattended-upgrades"          sh -c 'test -f /etc/apt/apt.conf.d/20auto-upgrades'
check "journald cap"                 sh -c 'test -f /etc/systemd/journald.conf.d/size-cap.conf'

echo "=== result: ${PASS} ok, ${FAIL} fail ==="
[ "${FAIL}" -eq 0 ] && echo "ALL GREEN — server ready for Tyler" || echo "RED — fix failures above"
exit "${FAIL}"
