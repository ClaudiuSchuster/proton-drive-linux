#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-account-switch.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

fake_bin="${test_root}/bin"
mkdir -p -- "${fake_bin}"

# Keep fixture expansions literal until the fake command runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "systemctl:%s\n" "$*" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    'case " $* " in' \
    '  *" show "*)' \
    '    state="$(cat "${PDRIVE_TEST_SERVICE_STATE}")"' \
    '    if [[ "${state}" == active ]]; then' \
    '      printf "ActiveState=active\nSubState=running\nMainPID=4242\n"' \
    '    else' \
    '      printf "ActiveState=inactive\nSubState=dead\nMainPID=0\n"' \
    '    fi' \
    '    ;;' \
    '  *" stop rclone-proton-drive.service "*) printf "inactive\n" > "${PDRIVE_TEST_SERVICE_STATE}" ;;' \
    '  *" start --no-block rclone-proton-drive.service "*) printf "active\n" > "${PDRIVE_TEST_SERVICE_STATE}" ;;' \
    'esac' \
    'exit 0' > "${fake_bin}/systemctl"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ "${1:-}" == -q ]] || exit 2' \
    '[[ "$(cat "${PDRIVE_TEST_SERVICE_STATE}")" == active ]] || exit 1' \
    'if [[ "${PDRIVE_TEST_FAIL_NEW_MOUNT:-}" == 1 && -e "${PDRIVE_ACCOUNT_CONFIG}" ]]; then exit 1; fi' \
    'exit 0' > "${fake_bin}/mountpoint"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$(cat "${PDRIVE_TEST_SERVICE_STATE}")" != active ]]; then exit 1; fi' \
    'if [[ "${PDRIVE_TEST_FAIL_NEW_MOUNT:-}" == 1 && -e "${PDRIVE_ACCOUNT_CONFIG}" ]]; then exit 1; fi' \
    'printf "fuse.rclone rw,nosuid,nodev\n"' > "${fake_bin}/findmnt"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "rclone:" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'printf " %q" "$@" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'printf "\n" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'config=""' \
    'for argument in "$@"; do case "${argument}" in --config=*) config="${argument#--config=}" ;; esac; done' \
    'case "$*" in' \
    '  *"obscure -"*) IFS= read -r _secret; printf "obscured-candidate\n" ;;' \
    '  *" config encryption set"*|*" config encryption check"*) exit 0 ;;' \
    '  *" config update proton 2fa "*) sed -i "/^2fa = /d" "${config}" ;;' \
    '  *" lsd proton:"*)' \
    '    printf "rclone:login\n" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    '    if [[ "${PDRIVE_TEST_RATE_LIMIT:-}" == 1 ]]; then printf "Status=429\n" >&2; exit 43; fi' \
    '    [[ "${PDRIVE_TEST_LOGIN_FAIL:-}" != 1 ]] || exit 42' \
    '    grep -qFx "password = obscured-candidate" "${config}"' \
    '    ;;' \
    '  *" vfs/queue"*)' \
    '    if [[ "${PDRIVE_TEST_QUEUE:-}" == 1 ]]; then printf "{\"queue\":[{\"name\":\"pending.bin\"}]}\n"; else printf "{\"queue\":[]}\n"; fi' \
    '    ;;' \
    '  *" core/stats"*)' \
    '    if [[ "${PDRIVE_TEST_TRANSFER:-}" == 1 ]]; then printf "{\"transferring\":[{\"name\":\"active.bin\"}]}\n"; else printf "{\"transferring\":[]}\n"; fi' \
    '    ;;' \
    '  *" core/pid"*) printf "{\"pid\":4242}\n" ;;' \
    '  *" vfs/stats"*)' \
    '    cache="${PDRIVE_CACHE_ROOT}"' \
    '    if [[ -r "${PDRIVE_ACCOUNT_CONFIG}" ]]; then namespace="$(cut -d= -f2 "${PDRIVE_ACCOUNT_CONFIG}" | tail -n 1)"; cache="${cache}/accounts/${namespace}"; fi' \
    '    printf "{\"diskCache\":{\"path\":\"%s/vfs/proton\",\"pathMeta\":\"%s/vfsMeta/proton\"}}\n" "${cache}" "${cache}"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "auth-guard:%s\n" "$*" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    '[[ "${PDRIVE_TEST_AUTH_GUARD_FAIL:-}" != 1 ]] || exit 44' \
    'if [[ "${1:-}" == --mark-healthy ]]; then printf "%s\n" "{\"schema_version\":1,\"status\":\"ready\",\"reason\":\"authenticated\",\"restart_suppressed\":false}" > "${PDRIVE_AUTH_STATE}"; fi' \
    'exit 0' > "${fake_bin}/pdrive-auth-failure-guard"

chmod 0755 "${fake_bin}"/*

setup_home() {
    local fixture_home="$1"
    mkdir -p -- \
        "${fixture_home}/.config/rclone" \
        "${fixture_home}/.local/state/rclone" \
        "${fixture_home}/.cache/rclone" \
        "${fixture_home}/mount"
    printf '%s\n' '[proton]' 'type = protondrive' 'old = current-account' \
        > "${fixture_home}/.config/rclone/rclone.conf"
    chmod 0600 "${fixture_home}/.config/rclone/rclone.conf"
    printf 'active\n' > "${fixture_home}/service-state"
    printf '%s\n' \
        '{"schema_version":1,"status":"ready","reason":"authenticated","restart_suppressed":false}' \
        > "${fixture_home}/.local/state/rclone/pdrive-auth-state.json"
    python3 - "${fixture_home}/.local/state/rclone/pdrive-rc.sock" <<'PY'
import socket
import sys

listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
listener.bind(sys.argv[1])
listener.close()
PY
}

run_fixture() {
    local fixture_home="$1"
    shift
    HOME="${fixture_home}" \
        PATH="${fake_bin}:/usr/bin:/bin" \
        PDRIVE_RCLONE_BIN="${fake_bin}/rclone" \
        PDRIVE_RCLONE_CONFIG="${fixture_home}/.config/rclone/rclone.conf" \
        PDRIVE_ACCOUNT_CONFIG="${fixture_home}/.config/pdrive-account.conf" \
        PDRIVE_CACHE_ROOT="${fixture_home}/.cache/rclone" \
        PDRIVE_STATE_DIR="${fixture_home}/.local/state/rclone" \
        PDRIVE_BACKUP_DIR="${fixture_home}/.config/rclone/backups" \
        PDRIVE_MOUNT_DIR="${fixture_home}/mount" \
        PDRIVE_RC_SOCKET="${fixture_home}/.local/state/rclone/pdrive-rc.sock" \
        PDRIVE_AUTH_STATE="${fixture_home}/.local/state/rclone/pdrive-auth-state.json" \
        PDRIVE_AUTH_GUARD="${fake_bin}/pdrive-auth-failure-guard" \
        PDRIVE_ACCOUNT_CACHE_HELPER="${project_dir}/libexec/pdrive-account-cache" \
        PDRIVE_ACCOUNT_SWITCH_MOUNT_ATTEMPTS=1 \
        PDRIVE_ACCOUNT_SWITCH_ROLLBACK_ATTEMPTS=1 \
        PDRIVE_ACCOUNT_SWITCH_POLL_SECONDS=0 \
        PDRIVE_TEST_ARGV_LOG="${fixture_home}/argv.log" \
        PDRIVE_TEST_EVENT_LOG="${fixture_home}/events.log" \
        PDRIVE_TEST_SERVICE_STATE="${fixture_home}/service-state" \
        "$@"
}

resolver_home="${test_root}/resolver-home"
mkdir -p -- "${resolver_home}/.config"
legacy_path="$(HOME="${resolver_home}" "${project_dir}/libexec/pdrive-account-cache" --path)"
[[ "${legacy_path}" == "${resolver_home}/.cache/rclone" ]]
printf '%s\n' 'cache_namespace=account-0123456789abcdef0123456789abcdef' \
    > "${resolver_home}/.config/pdrive-account.conf"
resolved_path="$(HOME="${resolver_home}" "${project_dir}/libexec/pdrive-account-cache" --path)"
[[ "${resolved_path}" == "${resolver_home}/.cache/rclone/accounts/account-0123456789abcdef0123456789abcdef" ]]
printf '%s\n' 'cache_namespace=../../unsafe' > "${resolver_home}/.config/pdrive-account.conf"
if HOME="${resolver_home}" "${project_dir}/libexec/pdrive-account-cache" --path >/dev/null 2>&1; then
    printf 'An unsafe account cache namespace was accepted.\n' >&2
    exit 1
fi

busy_home="${test_root}/busy-home"
setup_home "${busy_home}"
if PDRIVE_TEST_QUEUE=1 run_fixture "${busy_home}" \
    "${project_dir}/libexec/switch-rclone-proton-account" --preflight \
    > "${busy_home}/stdout" 2> "${busy_home}/stderr"; then
    printf 'An account change preflight accepted a queued upload.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=busy' "${busy_home}/stderr"
if grep -qF ' stop ' "${busy_home}/events.log"; then
    printf 'A blocked preflight changed the service lifecycle.\n' >&2
    exit 1
fi

dirty_home="${test_root}/dirty-home"
setup_home "${dirty_home}"
mkdir -p -- "${dirty_home}/.cache/rclone/vfsMeta/proton/fixture"
printf '%s\n' '{"Dirty":true,"Size":4096}' \
    > "${dirty_home}/.cache/rclone/vfsMeta/proton/fixture/pending.bin"
if run_fixture "${dirty_home}" \
    "${project_dir}/libexec/switch-rclone-proton-account" --preflight \
    > "${dirty_home}/stdout" 2> "${dirty_home}/stderr"; then
    printf 'An account change preflight accepted Dirty cache data.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=dirty-cache' "${dirty_home}/stderr"

test_username="candidate-$RANDOM-$RANDOM"
test_password="password-$RANDOM-$RANDOM-$RANDOM"
test_2fa="$(printf '%06d' "$((RANDOM % 1000000))")"

failed_home="${test_root}/failed-home"
setup_home "${failed_home}"
failed_before="$(sha256sum "${failed_home}/.config/rclone/rclone.conf")"
if printf '%s\0' "${test_username}" "${test_password}" "${test_2fa}" \
    | PDRIVE_TEST_LOGIN_FAIL=1 run_fixture "${failed_home}" \
        "${project_dir}/libexec/switch-rclone-proton-account" --switch-from-stdin \
        > "${failed_home}/stdout" 2> "${failed_home}/stderr"; then
    printf 'A failed candidate login was accepted.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${failed_home}/.config/rclone/rclone.conf")" == "${failed_before}" ]]
[[ ! -e "${failed_home}/.config/pdrive-account.conf" ]]
if grep -qF 'systemctl:--user stop' "${failed_home}/events.log"; then
    printf 'A failed candidate login stopped the current service.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=login-rejected' "${failed_home}/stderr"

rate_home="${test_root}/rate-home"
setup_home "${rate_home}"
if printf '%s\0' "${test_username}" "${test_password}" "${test_2fa}" \
    | PDRIVE_TEST_RATE_LIMIT=1 run_fixture "${rate_home}" \
        "${project_dir}/libexec/switch-rclone-proton-account" --switch-from-stdin \
        > "${rate_home}/stdout" 2> "${rate_home}/stderr"; then
    printf 'A rate-limited candidate login was accepted.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=rate-limited' "${rate_home}/stderr"
if grep -qF 'auth-guard:' "${rate_home}/events.log"; then
    printf 'Candidate rate limiting leaked into the same-account authentication guard.\n' >&2
    exit 1
fi

success_home="${test_root}/success-home"
setup_home "${success_home}"
if ! printf '%s\0' "${test_username}" "${test_password}" "${test_2fa}" \
    | run_fixture "${success_home}" \
        "${project_dir}/libexec/switch-rclone-proton-account" --switch-from-stdin \
        > "${success_home}/stdout" 2> "${success_home}/stderr"; then
    printf 'A valid candidate account switch failed:\n' >&2
    sed -n '1,20p' "${success_home}/stderr" >&2
    exit 1
fi
grep -qFx "username = ${test_username}" "${success_home}/.config/rclone/rclone.conf"
grep -qFx 'password = obscured-candidate' "${success_home}/.config/rclone/rclone.conf"
if grep -qF "${test_2fa}" "${success_home}/.config/rclone/rclone.conf"; then
    printf 'The one-time code remained in the installed configuration.\n' >&2
    exit 1
fi
namespace="$(awk -F= '$1 == "cache_namespace" { print $2 }' "${success_home}/.config/pdrive-account.conf")"
[[ "${namespace}" =~ ^account-[0-9a-f]{32}$ ]]
[[ -d "${success_home}/.cache/rclone/accounts/${namespace}" ]]
rollback_bundle="$(find "${success_home}/.config/rclone/backups" -mindepth 1 -maxdepth 1 \
    -type d -name 'account-switch-*' -print -quit)"
[[ -n "${rollback_bundle}" && -f "${rollback_bundle}/rclone.conf" ]]
grep -qF 'old = current-account' "${rollback_bundle}/rclone.conf"
login_line="$(grep -nF 'rclone:login' "${success_home}/events.log" | head -n 1 | cut -d: -f1)"
stop_line="$(grep -nF 'systemctl:--user stop rclone-proton-drive.service' \
    "${success_home}/events.log" | cut -d: -f1)"
(( login_line < stop_line ))
grep -qF 'auth-guard:--mark-healthy' "${success_home}/events.log"
if grep -RqsF "${test_password}" \
    "${success_home}/argv.log" "${success_home}/events.log" \
    "${success_home}/stdout" "${success_home}/stderr"; then
    printf 'The candidate password escaped into output, argv or lifecycle logs.\n' >&2
    exit 1
fi
if grep -RqsF "${test_username}" \
    "${success_home}/argv.log" "${success_home}/events.log" \
    "${success_home}/stdout" "${success_home}/stderr"; then
    printf 'The candidate account identifier escaped into output, argv or lifecycle logs.\n' >&2
    exit 1
fi

rollback_home="${test_root}/rollback-home"
setup_home "${rollback_home}"
rollback_before="$(sha256sum "${rollback_home}/.config/rclone/rclone.conf")"
if printf '%s\0' "${test_username}" "${test_password}" "${test_2fa}" \
    | PDRIVE_TEST_FAIL_NEW_MOUNT=1 run_fixture "${rollback_home}" \
        "${project_dir}/libexec/switch-rclone-proton-account" --switch-from-stdin \
        > "${rollback_home}/stdout" 2> "${rollback_home}/stderr"; then
    printf 'A candidate mount validation failure reported success.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=activation-failed-rolled-back' \
    "${rollback_home}/stderr"
[[ "$(sha256sum "${rollback_home}/.config/rclone/rclone.conf")" == "${rollback_before}" ]]
[[ ! -e "${rollback_home}/.config/pdrive-account.conf" ]]
[[ "$(cat "${rollback_home}/service-state")" == active ]]

activation_home="${test_root}/activation-home"
setup_home "${activation_home}"
activation_before="$(sha256sum "${activation_home}/.config/rclone/rclone.conf")"
if printf '%s\0' "${test_username}" "${test_password}" "${test_2fa}" \
    | PDRIVE_TEST_AUTH_GUARD_FAIL=1 run_fixture "${activation_home}" \
        "${project_dir}/libexec/switch-rclone-proton-account" --switch-from-stdin \
        > "${activation_home}/stdout" 2> "${activation_home}/stderr"; then
    printf 'A failed activation guard reported account-switch success.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_ACCOUNT_SWITCH_ERROR=activation-failed-rolled-back' \
    "${activation_home}/stderr"
[[ "$(sha256sum "${activation_home}/.config/rclone/rclone.conf")" == "${activation_before}" ]]
[[ ! -e "${activation_home}/.config/pdrive-account.conf" ]]
[[ "$(cat "${activation_home}/service-state")" == active ]]

printf 'PDrive guarded account-switch checks passed.\n'
