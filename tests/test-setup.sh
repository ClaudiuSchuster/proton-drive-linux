#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-setup.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

fake_bin="${test_root}/bin"
test_home="${test_root}/home"
mount_dir="${test_root}/mount"
mkdir -p -- "${fake_bin}" "${test_home}" "${mount_dir}"

# These single-quoted lines deliberately write literal shell expansions into
# the fake commands instead of expanding them in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  lookup) exit 1 ;;' \
    '  store) cat >/dev/null ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/secret-tool"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" >> "${PDRIVE_TEST_SYSTEMCTL_LOG}"' > "${fake_bin}/systemctl"
# The same applies to the fake rclone executable below.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf " %q" "$@" >> "${PDRIVE_TEST_RCLONE_ARGV_LOG}"' \
    'printf "\n" >> "${PDRIVE_TEST_RCLONE_ARGV_LOG}"' \
    'config=""' \
    'for argument in "$@"; do' \
    '  case "${argument}" in --config=*) config="${argument#--config=}" ;; esac' \
    'done' \
    'case "$*" in' \
    '  *"obscure -"*) read -r secret; [[ "${secret}" == "correct horse battery staple" ]]; printf "obscured-password\\n" ;;' \
    '  *" config encryption set"*|*" config encryption check"*) exit 0 ;;' \
    '  *" config update proton 2fa "*) sed -i '\''/^2fa = /d'\'' "${config}" ;;' \
    '  *" lsd proton:"*)' \
    '    [[ "${PDRIVE_TEST_LOGIN_FAIL:-}" != 1 ]] || exit 42' \
    '    grep -qFx '\''username = person@example.test'\'' "${config}"' \
    '    grep -qFx '\''password = obscured-password'\'' "${config}"' \
    '    grep -qFx '\''2fa = 123456'\'' "${config}"' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone"
chmod 0755 "${fake_bin}/secret-tool" "${fake_bin}/systemctl" "${fake_bin}/rclone"

systemctl_log="${test_root}/systemctl.log"
rclone_argv_log="${test_root}/rclone-argv.log"
setup_output="${test_root}/setup.out"
setup_error="${test_root}/setup.err"
if ! printf '%s\0' 'person@example.test' 'correct horse battery staple' '123456' \
    | HOME="${test_home}" \
        PATH="${fake_bin}:/usr/bin:/bin" \
        PDRIVE_MOUNT_DIR="${mount_dir}" \
        PDRIVE_RCLONE_BIN="${fake_bin}/rclone" \
        PDRIVE_TEST_RCLONE_ARGV_LOG="${rclone_argv_log}" \
        PDRIVE_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
        "${project_dir}/libexec/setup-rclone-proton" --setup-from-stdin \
        > "${setup_output}" 2> "${setup_error}"; then
    printf 'Transactional setup fixture failed:\n' >&2
    cat "${setup_error}" >&2
    exit 1
fi

config_file="${test_home}/.config/rclone/rclone.conf"
[[ -f "${config_file}" ]]
[[ "$(stat -c '%a' "${config_file}")" == 600 ]]
grep -qFx 'username = person@example.test' "${config_file}"
grep -qFx 'password = obscured-password' "${config_file}"
if grep -qF '123456' "${config_file}" \
    || grep -RqsE 'correct horse battery staple|123456' \
        "${setup_output}" "${setup_error}"; then
    printf 'A one-time code or password escaped the setup output or configuration.\n' >&2
    exit 1
fi
if grep -Eq 'correct\\ horse\\ battery\\ staple|123456' "${rclone_argv_log}"; then
    printf 'A password or one-time code escaped into an rclone process argument.\n' >&2
    exit 1
fi
grep -qF 'enable rclone-proton-drive.service pdrive-watch.timer rclone-selfupdate.timer' "${systemctl_log}"
grep -qF 'start --no-block rclone-proton-drive.service pdrive-watch.timer rclone-selfupdate.timer' "${systemctl_log}"

failed_home="${test_root}/failed-home"
mkdir -p -- "${failed_home}"
if printf '%s\0' 'person@example.test' 'correct horse battery staple' '123456' \
    | HOME="${failed_home}" \
        PATH="${fake_bin}:/usr/bin:/bin" \
        PDRIVE_MOUNT_DIR="${mount_dir}" \
        PDRIVE_RCLONE_BIN="${fake_bin}/rclone" \
        PDRIVE_TEST_RCLONE_ARGV_LOG="${rclone_argv_log}" \
        PDRIVE_TEST_LOGIN_FAIL=1 \
        PDRIVE_TEST_SYSTEMCTL_LOG="${systemctl_log}" \
        "${project_dir}/libexec/setup-rclone-proton" --setup-from-stdin \
        >/dev/null 2>&1; then
    printf 'A failed Proton login was accepted.\n' >&2
    exit 1
fi
[[ ! -e "${failed_home}/.config/rclone/rclone.conf" ]]
[[ -z "$(find "${failed_home}/.config/rclone" -maxdepth 1 -type f -name 'rclone.conf.*' -print -quit)" ]]
if grep -Eq 'correct\\ horse\\ battery\\ staple|123456' "${rclone_argv_log}"; then
    printf 'A failed setup exposed a password or one-time code in process arguments.\n' >&2
    exit 1
fi

printf 'PDrive transactional setup checks passed.\n'
