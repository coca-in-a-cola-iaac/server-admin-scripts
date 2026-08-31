#!/usr/bin/env bash
# 10-user.sh — provision agent user + passwordless sudo. Idempotent.
# Part of vps-hardening: run all scripts in numeric order as root.
set -euo pipefail

TYLER_USER="${TYLER_USER:-tyler}"
TYLER_SSH_KEY="${TYLER_SSH_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5REDACTED_KEY_MATERIAL tyler@example}"
SUDOERS_FILE="/etc/sudoers.d/${TYLER_USER}"

echo "=== [1/4] user ${TYLER_USER} ==="
if id "${TYLER_USER}" &>/dev/null; then
    echo "    user exists, ok"
else
    adduser --disabled-password --gecos "Tyler agent" "${TYLER_USER}"
    echo "    user created"
fi
usermod -aG sudo "${TYLER_USER}" 2>/dev/null || true

echo "=== [2/4] passwordless sudo ==="
TMP_SUDOERS="$(mktemp)"
echo "${TYLER_USER} ALL=(ALL) NOPASSWD:ALL" > "${TMP_SUDOERS}"
if visudo -cf "${TMP_SUDOERS}" >/dev/null; then
    install -m 440 -o root -g root "${TMP_SUDOERS}" "${SUDOERS_FILE}"
    echo "    sudoers ok (${SUDOERS_FILE})"
else
    echo "    ERROR: sudoers validation failed, aborting (no changes made)" >&2
    rm -f "${TMP_SUDOERS}"
    exit 1
fi
rm -f "${TMP_SUDOERS}"

echo "=== [3/4] ssh key ==="
HOMEDIR="$(getent passwd "${TYLER_USER}" | cut -d: -f6)"
[ -n "${HOMEDIR}" ] || HOMEDIR="/home/${TYLER_USER}"
install -d -m 700 -o "${TYLER_USER}" -g "${TYLER_USER}" "${HOMEDIR}/.ssh"
AUTHKEYS="${HOMEDIR}/.ssh/authorized_keys"
touch "${AUTHKEYS}"
chown "${TYLER_USER}:${TYLER_USER}" "${AUTHKEYS}"
chmod 600 "${AUTHKEYS}"
grep -qxF "${TYLER_SSH_KEY}" "${AUTHKEYS}" || echo "${TYLER_SSH_KEY}" >> "${AUTHKEYS}"
echo "    authorized_keys ok ($(grep -c . "${AUTHKEYS}") key(s))"

# Optional extra groups (docker etc.) — only existing ones
if [ -n "${TYLER_GROUPS:-}" ]; then
    IFS=',' read -ra GROUPS_ARR <<< "${TYLER_GROUPS}"
    for g in "${GROUPS_ARR[@]}"; do
        if getent group "${g}" >/dev/null; then
            usermod -aG "${g}" "${TYLER_USER}"
            echo "    added to group: ${g}"
        else
            echo "    group ${g} does not exist, skipped"
        fi
    done
fi

echo "=== [4/4] verify ==="
sudo -u "${TYLER_USER}" sudo -n true 2>/dev/null \
    && echo "    passwordless sudo: OK" \
    || { echo "    passwordless sudo: FAILED" >&2; exit 1; }
echo "=== 10-user done ==="
