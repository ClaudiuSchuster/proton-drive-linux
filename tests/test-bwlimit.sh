#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-bwlimit.XXXXXX)"
cleanup() {
    rm -rf -- "${test_root}"
}
trap cleanup EXIT

test_home="${test_root}/home"
state_dir="${test_root}/state"
socket_path="${state_dir}/pdrive-rc.sock"
fake_rclone="${test_root}/rclone"
runtime_state="${test_root}/runtime"
command_log="${test_root}/commands.log"
mkdir -p "${test_home}" "${state_dir}"
printf '%s\n' 'off:off' > "${runtime_state}"

cat > "${fake_rclone}" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

printf '%q ' "$@" >> "${PDRIVE_TEST_COMMAND_LOG}"
printf '\n' >> "${PDRIVE_TEST_COMMAND_LOG}"

if [[ "${1:-}" == rc && "${2:-}" == --loopback && "${3:-}" == core/bwlimit ]]; then
    rate="${4#rate=}"
    printf '{"rate":"%s"}\n' "${rate}"
    exit 0
fi

if [[ "${1:-}" == rc && "${2:-}" == --unix-socket ]]; then
    shift 3
    [[ "${1:-}" == backend/command ]]
    shift
    options=''
    for argument in "$@"; do
        case "${argument}" in
            command=data-bandwidth|fs=proton:) ;;
            opt=*) options="${argument#opt=}" ;;
            *) printf 'unexpected argument: %s\n' "${argument}" >&2; exit 2 ;;
        esac
    done
    if [[ -n "${options}" ]]; then
        upload="$(jq -r .upload <<< "${options}")"
        download="$(jq -r .download <<< "${options}")"
        printf '%s:%s\n' "${upload}" "${download}" > "${PDRIVE_TEST_RUNTIME_STATE}"
    fi
    IFS=: read -r upload download < "${PDRIVE_TEST_RUNTIME_STATE}"
    jq -cn --arg upload "${upload}" --arg download "${download}" \
        '{result: {upload: $upload, download: $download}}'
    exit 0
fi

exit 2
SH
chmod 0755 "${fake_rclone}"

run_helper() {
    HOME="${test_home}" \
        PDRIVE_RCLONE_STATE_DIR="${state_dir}" \
        PDRIVE_RC_SOCKET="${socket_path}" \
        PDRIVE_RCLONE_BIN="${fake_rclone}" \
        PDRIVE_BWLIMIT_TEST_SOCKET_READY=1 \
        PDRIVE_TEST_RUNTIME_STATE="${runtime_state}" \
        PDRIVE_TEST_COMMAND_LOG="${command_log}" \
        "${project_dir}/bin/pdrive-bwlimit" "$@"
}

run_helper 4.2 >/dev/null
grep -q '^bwlimit=4.2M:off$' "${test_home}/.config/pdrive-bwlimit.conf"
grep -q '^4.2M:off$' "${runtime_state}"

run_helper 1:0.5 >/dev/null
grep -q '^bwlimit=1M:0.5M$' "${test_home}/.config/pdrive-bwlimit.conf"
grep -q '^1M:0.5M$' "${runtime_state}"

status_output="$(run_helper --status)"
grep -qF 'Saved:         upload 1MB/s, download 0.5MB/s' <<< "${status_output}"
grep -qF 'Running rclone: upload 1MB/s, download 0.5MB/s' <<< "${status_output}"

printf '%s\n' 'bwlimit=800K:off' > "${test_home}/.config/pdrive-bwlimit.conf"
printf '%s\n' 'off:off' > "${runtime_state}"
run_helper --apply-startup >/dev/null
grep -q '^800K:off$' "${runtime_state}"

run_helper off >/dev/null
grep -q '^bwlimit=off$' "${test_home}/.config/pdrive-bwlimit.conf"
grep -q '^off:off$' "${runtime_state}"

if grep -q 'core/bwlimit.*--unix-socket\|--unix-socket.*core/bwlimit' "${command_log}"; then
    printf 'The live mount was changed through the global rclone limiter.\n' >&2
    exit 1
fi
grep -q 'backend/command.*command=data-bandwidth.*fs=proton:' "${command_log}"

printf 'Backend file-data bandwidth checks passed.\n'
