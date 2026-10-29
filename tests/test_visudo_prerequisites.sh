#!/usr/bin/env bash
# test_visudo_prerequisites.sh — Isolated fixture regression suite for visudo/sudo prerequisites
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/10-user.sh"
FIXTURE_TMP_BASE="${TMPDIR:-/home/tyler/.hermes/profiles/tyler/cache/scratch}/prereq_tests_$$"
BASH_RUNNER="$(command -v bash || echo "/bin/bash")"

mkdir -p "${FIXTURE_TMP_BASE}"
trap 'rm -rf "${FIXTURE_TMP_BASE}"' EXIT

PASSED_COUNT=0
FAILED_COUNT=0

log_pass() {
    echo "  [PASS] $1"
    PASSED_COUNT=$((PASSED_COUNT + 1))
}

log_fail() {
    echo "  [FAIL] $1: $2"
    FAILED_COUNT=$((FAILED_COUNT + 1))
}

# Helper to extract the prerequisite section directly from the production script
extract_prereq_snippet() {
    awk '
        /# --- ensure standard administrative paths/ { printing=1 }
        /# --- resolve the agent public key/ { printing=0 }
        printing { print }
    ' "${SCRIPT_UNDER_TEST}"
}

# Setup sandbox environment with mock utilities
setup_sandbox() {
    local sandbox_name="$1"
    local sdir="${FIXTURE_TMP_BASE}/${sandbox_name}"
    mkdir -p "${sdir}/bin" "${sdir}/admin_bin" "${sdir}/logs"
    ln -sf "${BASH_RUNNER}" "${sdir}/bin/bash"
    ln -sf "$(command -v touch || echo "/usr/bin/touch")" "${sdir}/bin/touch"
    ln -sf "$(command -v chmod || echo "/usr/bin/chmod")" "${sdir}/bin/chmod"

    # Mock apt-get
    cat <<'EOF' > "${sdir}/bin/apt-get"
#!/usr/bin/env bash
set -e
LOG_FILE="${TEST_SANDBOX_DIR}/logs/apt.log"
echo "apt-get $*" >> "${LOG_FILE}"

if [ "${MOCK_APT_FAIL_UPDATE:-0}" = "1" ] && [ "$1" = "update" ]; then
    echo "mock apt update failure" >&2
    exit 100
fi

if [ "${MOCK_APT_FAIL_INSTALL:-0}" = "1" ] && [ "$1" = "install" ]; then
    echo "mock apt install failure" >&2
    exit 101
fi

if [ "$1" = "install" ]; then
    if [ "${MOCK_APT_NOOP:-0}" = "1" ]; then
        exit 0
    fi
    for pkg in "$@"; do
        if [ "$pkg" = "sudo" ]; then
            touch "${TEST_SANDBOX_DIR}/bin/sudo" "${TEST_SANDBOX_DIR}/bin/visudo"
            chmod +x "${TEST_SANDBOX_DIR}/bin/sudo" "${TEST_SANDBOX_DIR}/bin/visudo"
        fi
        if [ "$pkg" = "passwd" ]; then
            touch "${TEST_SANDBOX_DIR}/bin/useradd" "${TEST_SANDBOX_DIR}/bin/chpasswd" "${TEST_SANDBOX_DIR}/bin/getent"
            chmod +x "${TEST_SANDBOX_DIR}/bin/useradd" "${TEST_SANDBOX_DIR}/bin/chpasswd" "${TEST_SANDBOX_DIR}/bin/getent"
        fi
    done
fi
exit 0
EOF
    chmod +x "${sdir}/bin/apt-get"

    # Mock mutating utilities to verify zero mutation
    for cmd in useradd usermod chpasswd adduser; do
        cat <<EOF > "${sdir}/bin/${cmd}"
#!/usr/bin/env bash
echo "${cmd} \$*" >> "\${TEST_SANDBOX_DIR}/logs/mutation.log"
exit 0
EOF
        chmod +x "${sdir}/bin/${cmd}"
    done

    # Mock id
    cat <<'EOF' > "${sdir}/bin/id"
#!/usr/bin/env bash
# Default: user does not exist
exit 1
EOF
    chmod +x "${sdir}/bin/id"

    # Mock install
    cat <<'EOF' > "${sdir}/bin/install"
#!/usr/bin/env bash
echo "install $*" >> "${TEST_SANDBOX_DIR}/logs/mutation.log"
exit 0
EOF
    chmod +x "${sdir}/bin/install"

    echo "${sdir}"
}

echo "Running Visudo Prerequisite Automated Regression Fixtures..."
echo "Target script: ${SCRIPT_UNDER_TEST}"

# -----------------------------------------------------------------------------
# Test 1: missing sudo+visudo -> installs sudo then discovers commands
# -----------------------------------------------------------------------------
test_missing_sudo_visudo_installs_and_discovers() {
    local tname="test_missing_sudo_visudo"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Provide base tools
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"

    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    local exit_code=0
    local output
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log_fail "Test 1" "Expected exit code 0, got ${exit_code}. Output: ${output}"
        return
    fi

    if ! grep -q "apt-get install -y -qq sudo" "${sdir}/logs/apt.log"; then
        log_fail "Test 1" "apt-get install sudo was not invoked. Log: $(cat "${sdir}/logs/apt.log")"
        return
    fi

    if [ ! -x "${sdir}/bin/sudo" ] || [ ! -x "${sdir}/bin/visudo" ]; then
        log_fail "Test 1" "Expected mock sudo and visudo to be installed and executable"
        return
    fi

    log_pass "missing sudo+visudo -> installs sudo then discovers commands"
}

# -----------------------------------------------------------------------------
# Test 2: second actual prerequisite invocation => no package call (idempotent)
# -----------------------------------------------------------------------------
test_second_invocation_no_package_call() {
    local tname="test_idempotent_second_run"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Provide base tools
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"

    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    # First run (installs sudo)
    (
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" >/dev/null 2>&1
    )

    # Clear log before second run
    > "${sdir}/logs/apt.log"

    local exit_code=0
    local output
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log_fail "Test 2" "Second run failed with exit code ${exit_code}. Output: ${output}"
        return
    fi

    if [ -s "${sdir}/logs/apt.log" ]; then
        log_fail "Test 2" "Expected no package calls on second run, got: $(cat "${sdir}/logs/apt.log")"
        return
    fi

    log_pass "second actual prerequisite invocation => no package call"
}

# -----------------------------------------------------------------------------
# Test 3: present => no package call
# -----------------------------------------------------------------------------
test_already_present_no_package_call() {
    local tname="test_present_no_call"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # All tools present from the start
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent" "${sdir}/bin/sudo" "${sdir}/bin/visudo"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent" "${sdir}/bin/sudo" "${sdir}/bin/visudo"

    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    local exit_code=0
    local output
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log_fail "Test 3" "Expected exit code 0, got ${exit_code}. Output: ${output}"
        return
    fi

    if [ -f "${sdir}/logs/apt.log" ] && [ -s "${sdir}/logs/apt.log" ]; then
        log_fail "Test 3" "Expected no apt calls when tools present, got: $(cat "${sdir}/logs/apt.log")"
        return
    fi

    log_pass "present => no package call"
}

# -----------------------------------------------------------------------------
# Test 4: missing admin PATH => finds /usr/sbin via safe mock
# -----------------------------------------------------------------------------
test_missing_admin_path_finds_usrsbin() {
    local tname="test_missing_admin_path"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Base tools present in sdir/bin
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"

    # visudo and sudo only present in safe mock admin directory (representing /usr/sbin)
    touch "${sdir}/admin_bin/visudo" "${sdir}/admin_bin/sudo"
    chmod +x "${sdir}/admin_bin/visudo" "${sdir}/admin_bin/sudo"

    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    # Wrapper script that intercepts command -v to safely simulate /usr/sbin containing admin_bin
    # without touching real /usr/sbin.
    local wrapper="${sdir}/test_exec.sh"
    cat <<EOF > "${wrapper}"
#!/usr/bin/env bash
set -euo pipefail
command() {
    if [ "\$1" = "-v" ]; then
        local target="\$2"
        local IFS=:
        for dir in \$PATH; do
            if [ "\$dir" = "/usr/sbin" ] && [ -x "${sdir}/admin_bin/\$target" ]; then
                echo "/usr/sbin/\$target"
                return 0
            elif [ -x "\$dir/\$target" ]; then
                echo "\$dir/\$target"
                return 0
            fi
        done
        return 1
    fi
    builtin command "\$@"
}

# Sourced prerequisite code directly from production script
${prereq_code}
EOF
    chmod +x "${wrapper}"

    local exit_code=0
    local output
    # Initial PATH deliberately does NOT include /usr/sbin
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" "${wrapper}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log_fail "Test 4" "Expected exit code 0, got ${exit_code}. Output: ${output}"
        return
    fi

    if [ -f "${sdir}/logs/apt.log" ] && [ -s "${sdir}/logs/apt.log" ]; then
        log_fail "Test 4" "Expected no package calls because /usr/sbin had binaries, got: $(cat "${sdir}/logs/apt.log")"
        return
    fi

    log_pass "missing admin PATH => finds /usr/sbin via safe mock"
}

# -----------------------------------------------------------------------------
# Test 5: apt update/install failure => nonzero and zero user mutation
# -----------------------------------------------------------------------------
test_apt_failure_nonzero_and_zero_mutation() {
    local tname="test_apt_failure"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Base tools present, sudo missing to trigger apt-get
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"

    # 5a. Test apt-get update failure
    local exit_code_update=0
    local output_update
    output_update="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin:/usr/bin:/bin"
        export MOCK_APT_FAIL_UPDATE=1
        export TYLER_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGenericMockKeyForTestPurpose1234567890"
        "${BASH_RUNNER}" "${SCRIPT_UNDER_TEST}" 2>&1
    )" || exit_code_update=$?

    if [ ${exit_code_update} -eq 0 ]; then
        log_fail "Test 5a" "Expected failure on apt update, but script exited 0. Output: ${output_update}"
        return
    fi

    if [ -f "${sdir}/logs/mutation.log" ] && [ -s "${sdir}/logs/mutation.log" ]; then
        log_fail "Test 5a" "User mutation occurred despite apt update failure: $(cat "${sdir}/logs/mutation.log")"
        return
    fi

    # 5b. Test apt-get install failure
    > "${sdir}/logs/apt.log"
    rm -f "${sdir}/logs/mutation.log"

    local exit_code_install=0
    local output_install
    output_install="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin:/usr/bin:/bin"
        export MOCK_APT_FAIL_INSTALL=1
        export TYLER_SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGenericMockKeyForTestPurpose1234567890"
        "${BASH_RUNNER}" "${SCRIPT_UNDER_TEST}" 2>&1
    )" || exit_code_install=$?

    if [ ${exit_code_install} -eq 0 ]; then
        log_fail "Test 5b" "Expected failure on apt install, but script exited 0. Output: ${output_install}"
        return
    fi

    if [ -f "${sdir}/logs/mutation.log" ] && [ -s "${sdir}/logs/mutation.log" ]; then
        log_fail "Test 5b" "User mutation occurred despite apt install failure: $(cat "${sdir}/logs/mutation.log")"
        return
    fi

    log_pass "apt update/install failure => nonzero and zero user mutation"
}

# -----------------------------------------------------------------------------
# Test 6: installer exits zero but binary absent => nonzero
# -----------------------------------------------------------------------------
test_installer_exits_zero_but_binary_absent() {
    local tname="test_binary_absent"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Base tools present, sudo missing
    touch "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"
    chmod +x "${sdir}/bin/useradd" "${sdir}/bin/chpasswd" "${sdir}/bin/getent"

    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    local exit_code=0
    local output
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        export MOCK_APT_NOOP=1
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -eq 0 ]; then
        log_fail "Test 6" "Expected nonzero exit code when binary absent after install, got 0"
        return
    fi

    if ! echo "${output}" | grep -q "ERROR: visudo/sudo still missing after prerequisite installation"; then
        log_fail "Test 6" "Missing expected error message. Output: ${output}"
        return
    fi

    log_pass "installer exits zero but binary absent => nonzero"
}

# -----------------------------------------------------------------------------
# Test 7: missing base tools triggers passwd, missing both triggers both
# -----------------------------------------------------------------------------
test_missing_base_and_sudo_triggers_both_packages() {
    local tname="test_missing_both"
    local sdir
    sdir="$(setup_sandbox "${tname}")"

    # Neither base tools nor sudo present
    local prereq_code
    prereq_code="$(extract_prereq_snippet)"

    local exit_code=0
    local output
    output="$(
        export TEST_SANDBOX_DIR="${sdir}"
        export PATH="${sdir}/bin"
        "${BASH_RUNNER}" -euo pipefail -c "${prereq_code}" 2>&1
    )" || exit_code=$?

    if [ ${exit_code} -ne 0 ]; then
        log_fail "Test 7" "Expected exit code 0, got ${exit_code}. Output: ${output}"
        return
    fi

    if ! grep -q "apt-get install -y -qq passwd sudo" "${sdir}/logs/apt.log"; then
        log_fail "Test 7" "Expected both passwd and sudo to be installed. Log: $(cat "${sdir}/logs/apt.log")"
        return
    fi

    if [ ! -x "${sdir}/bin/useradd" ] || [ ! -x "${sdir}/bin/sudo" ]; then
        log_fail "Test 7" "Expected all base and sudo binaries to be present"
        return
    fi

    log_pass "missing base tools + sudo -> installs both passwd and sudo"
}

# Run all test cases
test_missing_sudo_visudo_installs_and_discovers
test_second_invocation_no_package_call
test_already_present_no_package_call
test_missing_admin_path_finds_usrsbin
test_apt_failure_nonzero_and_zero_mutation
test_installer_exits_zero_but_binary_absent
test_missing_base_and_sudo_triggers_both_packages

echo ""
echo "=== Summary ==="
echo "Total tests run: $((PASSED_COUNT + FAILED_COUNT))"
echo "Passed: ${PASSED_COUNT}"
echo "Failed: ${FAILED_COUNT}"

if [ "${FAILED_COUNT}" -gt 0 ]; then
    exit 1
fi
exit 0
