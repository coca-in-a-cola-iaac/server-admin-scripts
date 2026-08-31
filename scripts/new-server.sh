#!/usr/bin/env bash
# new-server.sh — one-shot bootstrap: runs all scripts in order from this repo
# checkout. Clone the repo, run this, done.
#
# Usage (as root, inside the cloned repo):
#   bash scripts/new-server.sh [extra-ufw-ports...]
# Example:
#   bash scripts/new-server.sh 8443 20085
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRA_PORTS="${*:-}"

if [ ! -f "${SCRIPT_DIR}/10-user.sh" ]; then
    echo "ERROR: run this from inside the cloned admin-utils repo (scripts/ missing)" >&2
    exit 1
fi

echo "=== admin-utils bootstrap (EXTRA_PORTS='${EXTRA_PORTS}') ==="
export EXTRA_PORTS
for s in 10-user 20-sshd 30-ufw 40-fail2ban 50-basics; do
    echo "--- ${s} ---"
    bash "${SCRIPT_DIR}/${s}.sh"
done

echo "=== final gate ==="
bash "${SCRIPT_DIR}/90-verify.sh"
