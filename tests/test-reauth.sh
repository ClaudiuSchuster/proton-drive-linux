#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-reauth.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

fake_bin="${test_root}/bin"
mkdir -p -- "${fake_bin}"

# Keep every fake expansion literal until the fixture command runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "systemctl:%s\n" "$*" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    'exit 0' > "${fake_bin}/systemctl"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ "${1:-}" == -q ]]' \
    'exit 0' > "${fake_bin}/mountpoint"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "rclone:" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'printf " %q" "$@" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'printf "\n" >> "${PDRIVE_TEST_ARGV_LOG}"' \
    'config=""' \
    'log_file=""' \
    'for argument in "$@"; do' \
    '  case "${argument}" in' \
    '    --config=*) config="${argument#--config=}" ;;' \
    '    --log-file=*) log_file="${argument#--log-file=}" ;;' \
    '  esac' \
    'done' \
    'case "$*" in' \
    '  *" config show proton"*) cat "${config}" ;;' \
    '  *"obscure -"*)' \
    '    IFS= read -r secret' \
    '    [[ "${secret}" == "correct horse battery staple" ]]' \
    '    printf "obscured-new-password\n"' \
    '    ;;' \
    '  *" config encryption set"*|*" config encryption check"*) exit 0 ;;' \
    '  *" lsd proton:"*)' \
    '    printf "rclone:login\n" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    '    if [[ "${PDRIVE_TEST_RATE_LIMIT:-}" == 1 ]]; then' \
    '      printf "ERROR: login failed: Status=429\n" >> "${log_file}"' \
    '      exit 43' \
    '    fi' \
    '    [[ "${PDRIVE_TEST_LOGIN_FAIL:-}" != 1 ]] || exit 42' \
    '    grep -qFx "username = person@example.test" "${config}"' \
    '    grep -qFx "password = obscured-new-password" "${config}"' \
    '    grep -qFx "2fa = 123456" "${config}"' \
    '    ;;' \
    '  *" config update proton 2fa "*) sed -i "/^2fa = /d" "${config}" ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone"
chmod 0755 "${fake_bin}/systemctl" "${fake_bin}/mountpoint" "${fake_bin}/rclone"

# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "auth-guard:%s\n" "$*" >> "${PDRIVE_TEST_EVENT_LOG}"' \
    'exit 0' > "${fake_bin}/pdrive-auth-failure-guard"
chmod 0755 "${fake_bin}/pdrive-auth-failure-guard"

run_fixture() {
    local fixture_home="$1"
    shift
    HOME="${fixture_home}" \
        PATH="${fake_bin}:/usr/bin:/bin" \
        PDRIVE_RCLONE_BIN="${fake_bin}/rclone" \
        PDRIVE_RCLONE_CONFIG="${fixture_home}/.config/rclone/rclone.conf" \
        PDRIVE_STATE_DIR="${fixture_home}/.local/state/rclone" \
        PDRIVE_BACKUP_DIR="${fixture_home}/.config/rclone/backups" \
        PDRIVE_MOUNT_DIR="${fixture_home}/mount" \
        PDRIVE_AUTH_GUARD="${PDRIVE_TEST_AUTH_GUARD:-${fake_bin}/pdrive-auth-failure-guard}" \
        PDRIVE_TEST_ARGV_LOG="${fixture_home}/argv.log" \
        PDRIVE_TEST_EVENT_LOG="${fixture_home}/events.log" \
        "$@"
}

success_home="${test_root}/success-home"
mkdir -p -- "${success_home}/.config/rclone" "${success_home}/mount"
printf '%s\n' '[proton]' 'type = protondrive' 'username = person@example.test' \
    'mailbox_password = obscured-mailbox' 'old = configuration' \
    > "${success_home}/.config/rclone/rclone.conf"
chmod 0600 "${success_home}/.config/rclone/rclone.conf"

printf '%s\0' '' 'correct horse battery staple' '123456' \
    | run_fixture "${success_home}" \
        "${project_dir}/libexec/reauth-rclone-proton" --reauth-from-stdin \
        > "${success_home}/stdout" 2> "${success_home}/stderr"

new_config="${success_home}/.config/rclone/rclone.conf"
[[ "$(stat -c '%a' "${new_config}")" == 600 ]]
grep -qFx 'username = person@example.test' "${new_config}"
grep -qFx 'password = obscured-new-password' "${new_config}"
grep -qFx 'mailbox_password = obscured-mailbox' "${new_config}"
if grep -qF '123456' "${new_config}"; then
    printf 'The one-time code remained in the installed configuration.\n' >&2
    exit 1
fi
backup="$(find "${success_home}/.config/rclone/backups" -type f \
    -name 'rclone.conf.before-reauth-*' -print -quit)"
[[ -n "${backup}" && "$(stat -c '%a' "${backup}")" == 600 ]]
grep -qFx 'old = configuration' "${backup}"
login_line="$(grep -nF 'rclone:login' "${success_home}/events.log" | cut -d: -f1)"
stop_line="$(grep -nF 'systemctl:--user stop rclone-proton-drive.service' \
    "${success_home}/events.log" | cut -d: -f1)"
(( login_line < stop_line ))
grep -qF 'systemctl:--user start --no-block rclone-proton-drive.service' \
    "${success_home}/events.log"
grep -qF 'auth-guard:--mark-healthy' "${success_home}/events.log"
if grep -RqsF 'correct horse battery staple' \
    "${success_home}/argv.log" "${success_home}/stdout" "${success_home}/stderr" \
    "${success_home}/.local/state/rclone/proton-reauth.log"; then
    printf 'The Proton password escaped into reauthentication output or argv.\n' >&2
    exit 1
fi
if grep -qsF '123456' "${success_home}/argv.log"; then
    printf 'The one-time code escaped into an rclone process argument.\n' >&2
    exit 1
fi
[[ -z "$(find "${success_home}/.local/state/rclone" -maxdepth 1 \
    -type d -name 'reauth-cache.*' -print -quit)" ]]

missing_guard_home="${test_root}/missing-guard-home"
mkdir -p -- "${missing_guard_home}/.config/rclone" "${missing_guard_home}/mount"
printf '%s\n' '[proton]' 'type = protondrive' 'username = person@example.test' \
    'old = guard-required' > "${missing_guard_home}/.config/rclone/rclone.conf"
chmod 0600 "${missing_guard_home}/.config/rclone/rclone.conf"
if printf '%s\0' '' 'correct horse battery staple' '123456' \
    | PDRIVE_TEST_AUTH_GUARD="${fake_bin}/missing-auth-guard" \
        run_fixture "${missing_guard_home}" \
        "${project_dir}/libexec/reauth-rclone-proton" --reauth-from-stdin \
        > "${missing_guard_home}/stdout" 2> "${missing_guard_home}/stderr"; then
    printf 'Reauthentication ran without its lifecycle guard.\n' >&2
    exit 1
fi
grep -qF 'Missing authentication lifecycle guard' "${missing_guard_home}/stderr"
[[ ! -e "${missing_guard_home}/events.log" ]]

failed_home="${test_root}/failed-home"
mkdir -p -- "${failed_home}/.config/rclone" "${failed_home}/mount"
printf '%s\n' '[proton]' 'type = protondrive' 'mailbox_password = obscured-mailbox' 'old = untouched' \
    > "${failed_home}/.config/rclone/rclone.conf"
chmod 0600 "${failed_home}/.config/rclone/rclone.conf"
before_sha="$(sha256sum "${failed_home}/.config/rclone/rclone.conf")"
if printf '%s\0' 'person@example.test' 'correct horse battery staple' '123456' \
    | PDRIVE_TEST_LOGIN_FAIL=1 run_fixture "${failed_home}" \
        "${project_dir}/libexec/reauth-rclone-proton" --reauth-from-stdin \
        > "${failed_home}/stdout" 2> "${failed_home}/stderr"; then
    printf 'A failed reauthentication login was accepted.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${failed_home}/.config/rclone/rclone.conf")" == "${before_sha}" ]]
if grep -qF 'systemctl:' "${failed_home}/events.log"; then
    printf 'A failed login changed the service lifecycle.\n' >&2
    exit 1
fi
if grep -qF 'auth-guard:' "${failed_home}/events.log"; then
    printf 'A failed login changed the authentication state.\n' >&2
    exit 1
fi
grep -qF 'PDRIVE_REAUTH_ERROR=login-rejected' "${failed_home}/stderr"
if grep -qF 'PDRIVE_REAUTH_ERROR=rate-limited' "${failed_home}/stderr"; then
    printf 'A generic rejected login was misclassified as rate-limited.\n' >&2
    exit 1
fi

rate_limited_home="${test_root}/rate-limited-home"
mkdir -p -- "${rate_limited_home}/.config/rclone" "${rate_limited_home}/mount"
printf '%s\n' '[proton]' 'type = protondrive' 'username = person@example.test' \
    'old = rate-limit-untouched' > "${rate_limited_home}/.config/rclone/rclone.conf"
chmod 0600 "${rate_limited_home}/.config/rclone/rclone.conf"
rate_limited_before="$(sha256sum "${rate_limited_home}/.config/rclone/rclone.conf")"
if printf '%s\0' '' 'correct horse battery staple' '123456' \
    | PDRIVE_TEST_RATE_LIMIT=1 run_fixture "${rate_limited_home}" \
        "${project_dir}/libexec/reauth-rclone-proton" --reauth-from-stdin \
        > "${rate_limited_home}/stdout" 2> "${rate_limited_home}/stderr"; then
    printf 'A rate-limited reauthentication was accepted.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${rate_limited_home}/.config/rclone/rclone.conf")" \
    == "${rate_limited_before}" ]]
grep -qF 'PDRIVE_REAUTH_ERROR=rate-limited' "${rate_limited_home}/stderr"
grep -qF 'auth-guard:--mark-rate-limited' "${rate_limited_home}/events.log"
if grep -qF 'systemctl:' "${rate_limited_home}/events.log"; then
    printf 'A rate-limited login changed the service lifecycle.\n' >&2
    exit 1
fi
[[ ! -d "${failed_home}/.config/rclone/backups" \
    || -z "$(find "${failed_home}/.config/rclone/backups" -type f -print -quit)" ]]

printf 'PDrive transactional reauthentication checks passed.\n'
