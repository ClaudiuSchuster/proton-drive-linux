#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-prerequisites.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
bootstrap="${test_root}/bootstrap-rclone"
target="${test_home}/.local/libexec/rclone-bin"
mkdir -p -- "${test_home}"

# Preserve the expansions for the fake process rather than this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  selfupdate) [[ "${2:-}" == --beta && "${3:-}" == --version && "${4:-}" == v1.76.0-beta.10204.660144d31 ]] ;;' \
    '  version) printf "rclone v1.76.0-beta.10204.660144d31\n" ;;' \
    '  help) [[ "${2:-}" == backend && "${3:-}" == protondrive ]] ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${bootstrap}"
chmod 0755 "${bootstrap}"

if HOME="${test_home}" PDRIVE_REAL_RCLONE="${target}" \
    "${project_dir}/bin/pdrive-prerequisites" --check >/dev/null 2>&1; then
    printf 'A missing user-local rclone passed prerequisite validation.\n' >&2
    exit 1
fi

HOME="${test_home}" \
    PDRIVE_REAL_RCLONE="${target}" \
    PDRIVE_BOOTSTRAP_RCLONE="${bootstrap}" \
    "${project_dir}/bin/pdrive-prerequisites" --install-rclone >/dev/null
HOME="${test_home}" PDRIVE_REAL_RCLONE="${target}" \
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
    '  *) exit 2 ;;' \
    'esac' > "${unsafe_target}"
chmod 0755 "${unsafe_target}"
if HOME="${test_home}" PDRIVE_REAL_RCLONE="${unsafe_target}" \
    "${project_dir}/bin/pdrive-prerequisites" --check >/dev/null 2>&1; then
    printf 'An upload-unsafe rclone passed prerequisite validation.\n' >&2
    exit 1
fi

printf 'PDrive prerequisite bootstrap checks passed.\n'
