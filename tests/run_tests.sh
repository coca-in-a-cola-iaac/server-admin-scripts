#!/usr/bin/env bash
# run_tests.sh — Test runner for server-admin-scripts regression suite
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== Running Server Admin Scripts Test Suite ==="

exit_code=0
for test_script in "${TEST_DIR}"/test_*.sh; do
    if [ -f "${test_script}" ]; then
        echo "--> Running $(basename "${test_script}")"
        bash "${test_script}" || exit_code=$?
    fi
done

if [ ${exit_code} -eq 0 ]; then
    echo "=== All test suites PASSED ==="
else
    echo "=== Some tests FAILED (exit code: ${exit_code}) ==="
fi

exit ${exit_code}
