#!/usr/bin/env bash
# new-server.sh — one-shot bootstrap: runs all scripts in order from this repo
# checkout. Clone the repo, run this, done.
#
# Usage (as root, inside the cloned repo):
#   bash scripts/new-server.sh [extra-ufw-ports...]
# Example:
#   bash scripts/new-server.sh 8443 20085
#
# The agent SSH public key is required. Either export it beforehand:
#   TYLER_SSH_KEY="$(cat ~/.ssh/id_ed25519.pub)" bash scripts/new-server.sh
# or just run this from an interactive shell and paste it when prompted.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_PORTS="${*:-}"

if [ ! -f "${SCRIPT_DIR}/10-user.sh" ]; then
    echo "ERROR: run this from inside the cloned admin-utils repo (scripts/ missing)" >&2
    exit 1
fi

# Pre-flight the SSH key so the user is not surprised mid-run. If it is not in the
# environment, prompt ONCE here (interactive) — 10-user.sh then reads it from env.
if [ -z "${TYLER_SSH_KEY:-}" ]; then
    if [ -t 0 ]; then
        echo "This bootstrap needs the agent user public key."
        echo "On YOUR machine find it with:  cat ~/.ssh/id_ed25519.pub"
        read -r -p "Paste public key here: " TYLER_SSH_KEY
        export TYLER_SSH_KEY
    else
        echo "ERROR: TYLER_SSH_KEY is not set and stdin is not a terminal." >&2
        echo "  Run:  TYLER_SSH_KEY=\"\$(cat ~/.ssh/id_ed25519.pub)\" bash scripts/new-server.sh" >&2
        exit 1
    fi
fi

echo "=== admin-utils bootstrap (EXTRA_PORTS='${EXTRA_PORTS}') ==="
export EXTRA_PORTS
for s in 10-user 20-sshd 30-ufw 40-fail2ban 50-basics; do
    echo "--- ${s} ---"
    bash "${SCRIPT_DIR}/${s}.sh"
done

echo "=== final gate ==="
bash "${SCRIPT_DIR}/90-verify.sh"
