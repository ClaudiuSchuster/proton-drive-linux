#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-updaters.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

fake_bin="${test_root}/bin"
mkdir -p -- "${fake_bin}"

# Preserve all expansions for the fake commands themselves.
# The expansions belong to the generated fixture, not this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "${PDRIVE_TEST_ARCH:-x86_64}"' > "${fake_bin}/uname"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'output=""' \
    'url=""' \
    'while (( $# )); do' \
    '  case "$1" in' \
    '    --output) output="$2"; shift 2 ;;' \
    '    https://*) url="$1"; shift ;;' \
    '    *) shift ;;' \
    '  esac' \
    'done' \
    'printf "%s\n" "${url}" >> "${PDRIVE_TEST_CURL_LOG}"' \
    'case "${url}" in' \
    '  */index.html)' \
    '    printf "%s\n" "<h1>Proton Drive CLI 1.2.3</h1>" "<tr>" "<td>linux/x64</td>" "<td><a href=\"https://proton.me/download/drive/cli/1.2.3/linux-x64/proton-drive\">download</a></td>" "<td><code>${PDRIVE_TEST_EXPECTED_SHA}</code></td>" "</tr>" > "${output}"' \
    '    ;;' \
    '  */1.2.3/linux-x64/proton-drive) cp -- "${PDRIVE_TEST_DOWNLOAD}" "${output}" ;;' \
    '  *) exit 22 ;;' \
    'esac' > "${fake_bin}/curl"
chmod 0755 "${fake_bin}/uname" "${fake_bin}/curl"

download_fixture="${test_root}/proton-drive-download"
# The expansion belongs to the generated fixture, not this test process.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' '[[ "${1:-}" == version ]]' 'printf "Proton Drive CLI 1.2.3\n"' \
    > "${download_fixture}"
chmod 0755 "${download_fixture}"
download_sha="$(sha512sum "${download_fixture}" | cut -d ' ' -f 1)"

success_home="${test_root}/success-home"
mkdir -p -- "${success_home}"
HOME="${success_home}" \
    XDG_STATE_HOME="${success_home}/.local/state" \
    PATH="${fake_bin}:/usr/bin:/bin" \
    PDRIVE_TEST_EXPECTED_SHA="${download_sha}" \
    PDRIVE_TEST_DOWNLOAD="${download_fixture}" \
    PDRIVE_TEST_CURL_LOG="${success_home}/curl.log" \
    "${project_dir}/libexec/proton-drive-update" >/dev/null
installed_cli="${success_home}/.local/bin/proton-drive"
[[ -x "${installed_cli}" && "$(stat -c '%a' "${installed_cli}")" == 755 ]]
[[ "$("${installed_cli}" version)" == 'Proton Drive CLI 1.2.3' ]]
grep -qFx '1.2.3' "${success_home}/.local/state/proton-drive-updater/installed-version"
[[ -z "$(find "${success_home}/.local/bin" "${success_home}/.local/state/proton-drive-updater" \
    -maxdepth 1 \( -name '.proton-drive.*' -o -name '.installed-version.*' -o -name 'update.*' \) \
    -print -quit)" ]]

failure_home="${test_root}/failure-home"
mkdir -p -- "${failure_home}/.local/bin"
printf 'existing binary\n' > "${failure_home}/.local/bin/proton-drive"
before_sha="$(sha256sum "${failure_home}/.local/bin/proton-drive")"
if HOME="${failure_home}" \
    XDG_STATE_HOME="${failure_home}/.local/state" \
    PATH="${fake_bin}:/usr/bin:/bin" \
    PDRIVE_TEST_EXPECTED_SHA="$(printf '0%.0s' {1..128})" \
    PDRIVE_TEST_DOWNLOAD="${download_fixture}" \
    PDRIVE_TEST_CURL_LOG="${failure_home}/curl.log" \
    "${project_dir}/libexec/proton-drive-update" >/dev/null 2>&1; then
    printf 'The Proton CLI updater accepted an invalid checksum.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${failure_home}/.local/bin/proton-drive")" == "${before_sha}" ]]

arch_home="${test_root}/arch-home"
mkdir -p -- "${arch_home}"
if HOME="${arch_home}" \
    PATH="${fake_bin}:/usr/bin:/bin" \
    PDRIVE_TEST_ARCH=aarch64 \
    PDRIVE_TEST_CURL_LOG="${arch_home}/curl.log" \
    "${project_dir}/libexec/proton-drive-update" >/dev/null 2>&1; then
    printf 'The x86-64 Proton CLI updater accepted an unsupported architecture.\n' >&2
    exit 1
fi
[[ ! -e "${arch_home}/curl.log" ]]

rclone_home="${test_root}/rclone-home"
mkdir -p -- "${rclone_home}/.local/libexec"
rclone_state="${rclone_home}/rclone-version"
printf 'rclone v1.0.0\n' > "${rclone_state}"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "${PDRIVE_TEST_RCLONE_LOG}"' \
    'case "${1:-}" in' \
    '  version) cat "${PDRIVE_TEST_RCLONE_STATE}" ;;' \
    '  selfupdate) printf "rclone v1.0.1\n" > "${PDRIVE_TEST_RCLONE_STATE}" ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${rclone_home}/.local/libexec/rclone-bin"
chmod 0755 "${rclone_home}/.local/libexec/rclone-bin"
HOME="${rclone_home}" \
    PDRIVE_TEST_RCLONE_LOG="${rclone_home}/rclone.log" \
    PDRIVE_TEST_RCLONE_STATE="${rclone_state}" \
    "${project_dir}/libexec/rclone-selfupdate" > "${rclone_home}/stdout"
grep -qFx 'selfupdate --stable' "${rclone_home}/rclone.log"
grep -qF 'Updated rclone v1.0.0 to rclone v1.0.1.' "${rclone_home}/stdout"

printf 'rclone v1.76.0-beta.10204.660144d31\n' > "${rclone_state}"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "${PDRIVE_TEST_RCLONE_LOG}"' \
    'case "${1:-}" in' \
    '  version) cat "${PDRIVE_TEST_RCLONE_STATE}" ;;' \
    '  selfupdate)' \
    '    if [[ "${2:-}" == --stable && "${3:-}" == --check ]]; then' \
    '      printf "Without --check this would install rclone version v1.75.0 at test-bin\n"' \
    '    else' \
    '      printf "Unexpected beta transition\n" >&2; exit 2' \
    '    fi' \
    '    ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${rclone_home}/.local/libexec/rclone-bin"
chmod 0755 "${rclone_home}/.local/libexec/rclone-bin"
: > "${rclone_home}/rclone.log"
HOME="${rclone_home}" \
    PDRIVE_TEST_RCLONE_LOG="${rclone_home}/rclone.log" \
    PDRIVE_TEST_RCLONE_STATE="${rclone_state}" \
    "${project_dir}/libexec/rclone-selfupdate" > "${rclone_home}/stdout"
grep -qFx 'selfupdate --stable --check' "${rclone_home}/rclone.log"
grep -qF 'Keeping rclone v1.76.0-beta.10204.660144d31 until a stable rclone release reaches v1.76.0.' \
    "${rclone_home}/stdout"
if grep -qFx 'selfupdate --stable' "${rclone_home}/rclone.log"; then
    printf 'The updater downgraded the upload-safe beta to an older stable release.\n' >&2
    exit 1
fi

printf 'PDrive updater integrity checks passed.\n'
