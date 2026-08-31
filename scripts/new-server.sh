#!/usr/bin/env bash
# new-server.sh — one-shot bootstrap: clones vps-hardening (or receives it via scp)
# and runs all scripts in order. Run as root on a brand-new Debian/Ubuntu VPS.
#
# Usage:
#   bash new-server.sh <repo-ssh-url> [extra-ufw-ports...]
# Example:
#   bash new-server.sh git@github.com:coca-in-a-cola-iaac/vps-hardening.git 8443 20085
set -euo pipefail

REPO_URL="${1:?usage: new-server.sh <repo-url> [extra-ports...]}"
shift || true
EXTRA_PORTS="${*:-}"

command -v git >/dev/null || { apt-get update -qq && apt-get install -y -qq git; }

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

echo "=== fetching vps-hardening ==="
GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new" \
    git clone --depth 1 "${REPO_URL}" "${WORKDIR}/repo" 2>&1 | tail -1

echo "=== running bootstrap (EXTRA_PORTS='${EXTRA_PORTS}') ==="
export EXTRA_PORTS
for s in 10-user 20-sshd 30-ufw 40-fail2ban 50-basics; do
    echo "--- ${s} ---"
    bash "${WORKDIR}/repo/scripts/${s}.sh"
done

echo "=== final gate ==="
bash "${WORKDIR}/repo/scripts/90-verify.sh"
