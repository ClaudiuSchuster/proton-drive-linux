#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-prerequisites.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
download="${test_root}/rclone-pdrive-download"
fake_curl="${test_root}/curl"
target="${test_home}/.local/libexec/rclone-bin"
mkdir -p -- "${test_home}"

# Preserve the expansions for the fake process rather than this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  version) printf "rclone v1.76.0-beta.10204.660144d31\n" ;;' \
    '  help) [[ "${2:-}" == backend && "${3:-}" == protondrive ]] ;;' \
    '  backend) [[ "${2:-}" == help && "${3:-}" == protondrive ]] && printf "### data-bandwidth\n" ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${download}"
chmod 0755 "${download}"
download_sha="$(sha256sum "${download}" | cut -d ' ' -f 1)"

# Preserve the expansions for the fake downloader rather than this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'output=""' \
    'while (( $# )); do' \
    '  case "$1" in --output) output="$2"; shift 2 ;; *) shift ;; esac' \
    'done' \
    'cp -- "${PDRIVE_TEST_RCLONE_DOWNLOAD}" "${output}"' \
    > "${fake_curl}"
chmod 0755 "${fake_curl}"

if HOME="${test_home}" PDRIVE_REAL_RCLONE="${target}" \
    "${project_dir}/bin/pdrive-prerequisites" --check >/dev/null 2>&1; then
    printf 'A missing user-local rclone passed prerequisite validation.\n' >&2
    exit 1
fi

HOME="${test_home}" \
    PDRIVE_REAL_RCLONE="${target}" \
    PDRIVE_CURL_BIN="${fake_curl}" \
    PDRIVE_RCLONE_URL='https://example.test/rclone-pdrive-linux-amd64' \
    PDRIVE_RCLONE_SHA256="${download_sha}" \
    PDRIVE_TEST_RCLONE_DOWNLOAD="${download}" \
    "${project_dir}/bin/pdrive-prerequisites" --install-rclone >/dev/null
HOME="${test_home}" PDRIVE_REAL_RCLONE="${target}" PDRIVE_RCLONE_SHA256="${download_sha}" \
    "${project_dir}/bin/pdrive-prerequisites" --check >/dev/null
[[ -x "${target}" ]]

unsafe_target="${test_home}/.local/libexec/rclone-unsafe"
# Preserve the expansions for the fake process rather than this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  version) printf "rclone v1.75.0\n" ;;' \
    '  help) exit 0 ;;' \
    '  backend) printf "### data-bandwidth\n" ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${unsafe_target}"
chmod 0755 "${unsafe_target}"
if HOME="${test_home}" PDRIVE_REAL_RCLONE="${unsafe_target}" \
    "${project_dir}/bin/pdrive-prerequisites" --check >/dev/null 2>&1; then
    printf 'An upload-unsafe rclone passed prerequisite validation.\n' >&2
    exit 1
fi

before_sha="$(sha256sum "${target}")"
if HOME="${test_home}" \
    PDRIVE_REAL_RCLONE="${target}" \
    PDRIVE_CURL_BIN="${fake_curl}" \
    PDRIVE_RCLONE_URL='https://example.test/rclone-pdrive-linux-amd64' \
    PDRIVE_RCLONE_SHA256="$(printf '0%.0s' {1..64})" \
    PDRIVE_TEST_RCLONE_DOWNLOAD="${download}" \
    "${project_dir}/bin/pdrive-prerequisites" --install-rclone >/dev/null 2>&1; then
    printf 'A PDrive rclone download with an invalid checksum was accepted.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${target}")" == "${before_sha}" ]]

printf 'PDrive prerequisite bootstrap checks passed.\n'
