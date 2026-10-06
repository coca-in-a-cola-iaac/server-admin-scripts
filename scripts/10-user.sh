#!/usr/bin/env bash
# 10-user.sh — provision agent user + passwordless sudo. Idempotent.
# Part of admin-utils: run all scripts in numeric order as root.
set -euo pipefail

TYLER_USER="${TYLER_USER:-tyler}"
SUDOERS_FILE="/etc/sudoers.d/${TYLER_USER}"

# --- ensure the base tools we need exist (minimal Debian/Ubuntu images lack adduser) ---
need_pkg() { command -v "$1" >/dev/null 2>&1; }
if ! need_pkg useradd || ! need_pkg chpasswd || ! need_pkg getent; then
    echo "=== installing prerequisites (passwd) ==="
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq passwd
fi

# --- resolve the agent public key: env > prompt ---
# Set TYLER_SSH_KEY in the environment to run non-interactively, e.g.
#   TYLER_SSH_KEY="$(cat ~/.ssh/id_ed25519.pub)" bash scripts/new-server.sh
# Never hardcode a key here: this repo is public.
if [ -z "${TYLER_SSH_KEY:-}" ]; then
    if [ -t 0 ]; then
        echo "Paste the agent user public key (ssh-ed25519 AAAA... or ssh-rsa AAAA...)."
        echo "Tip: find it with  cat ~/.ssh/id_ed25519.pub  on YOUR machine."
        read -r -p "Public key: " TYLER_SSH_KEY
    else
        echo "ERROR: TYLER_SSH_KEY is not set and stdin is not a terminal." >&2
        echo "  Set it:  TYLER_SSH_KEY=\"\$(cat ~/.ssh/id_ed25519.pub)\" bash scripts/new-server.sh" >&2
        echo "  Or run this script from an interactive shell to be prompted." >&2
        exit 1
    fi
fi

# --- basic validation: must look like an SSH public key ---
case "${TYLER_SSH_KEY}" in
    ssh-ed25519\ AAAA*|ssh-rsa\ AAAA*|ecdsa-sha2-*\ AAAA*|sk-ssh-*\ AAAA*|sk-ecdsa-*\ AAAA*)
        ;;
    *)
        echo "ERROR: TYLER_SSH_KEY does not look like an SSH public key." >&2
        echo "  Got: ${TYLER_SSH_KEY:0:40}..." >&2
        exit 1
        ;;
esac

echo "=== [1/4] user ${TYLER_USER} ==="
if id "${TYLER_USER}" &>/dev/null; then
    echo "    user exists, ok"
else
    # useradd ships in the always-present 'passwd' package; adduser does NOT exist
    # on minimal Debian/Ubuntu cloud images. Use useradd, fall back to adduser.
    if need_pkg useradd; then
        useradd --create-home --shell /bin/bash --comment "Tyler agent" "${TYLER_USER}"
    else
        adduser --disabled-password --gecos "Tyler agent" "${TYLER_USER}"
    fi
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
