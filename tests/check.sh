#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_version="$(< "${project_dir}/VERSION")"
if [[ ! "${project_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf 'Invalid project version: %s\n' "${project_version}" >&2
    exit 1
fi
grep -qF "VERSION = \"${project_version}\"" "${project_dir}/bin/pdrive-ui"
grep -qF "TOOL_VERSION = \"${project_version}\"" "${project_dir}/bin/pdrive-state"

mapfile -t shell_files < <(
    find "${project_dir}/bin" "${project_dir}/libexec" "${project_dir}/tests" \
        -maxdepth 1 -type f -name '*.sh' -print | sort
    printf '%s\n' "${project_dir}/install.sh" "${project_dir}/uninstall.sh"
)

for shell_file in "${shell_files[@]}"; do
    bash -n "${shell_file}"
done

for python_file in "${project_dir}/bin/pdrive-state" "${project_dir}/bin/pdrive-ui"; do
    python3 - "${python_file}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${shell_files[@]}"
else
    printf 'shellcheck not installed; static lint skipped.\n' >&2
fi

for shell_file in "${project_dir}"/bin/* "${project_dir}"/libexec/* \
    "${project_dir}"/install.sh "${project_dir}"/uninstall.sh "${project_dir}"/tests/*.sh; do
    [[ -x "${shell_file}" ]] || {
        printf 'Expected executable file: %s\n' "${shell_file}" >&2
        exit 1
    }
done

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate \
        "${project_dir}/share/applications/io.github.claudiuschuster.PDriveControl.desktop"
fi

if grep -RInE --exclude-dir=.git --exclude=check.sh \
    '(/home/claudiu|Claudiu Schuster|mail@claudiuschuster|VyrwC|BoundInLove|Fit4FunX|RCLONE_ENCRYPT_V0)' \
    "${project_dir}"; then
    printf 'Deployment-specific or sensitive material found.\n' >&2
    exit 1
fi

required_documentation=(
    'mode-0700 Unix'
    'Exact watchdog safety gates'
    'Reading counters correctly'
    $'FUSE reports `Operation not permitted`'
    'Keyring remains unavailable after login'
    $'After `apt autoremove`'
    'Backup and restoration'
    'Update schedule and integrity'
    'A link is not the same as a working route'
)
for required_text in "${required_documentation[@]}"; do
    if ! grep -RiqF -- "${required_text}" \
        "${project_dir}/README.md" "${project_dir}/docs"; then
        printf 'Required generic documentation is missing: %s\n' "${required_text}" >&2
        exit 1
    fi
done
if grep -RiqF -- 'mode-0600 Unix' "${project_dir}/README.md" "${project_dir}/docs"; then
    printf 'Incorrect RC Unix-socket mode found in documentation.\n' >&2
    exit 1
fi

"${project_dir}/tests/test-help.sh"
"${project_dir}/tests/test-systemd.sh"
"${project_dir}/tests/test-updaters.sh"
"${project_dir}/tests/test-cache-age.sh"
"${project_dir}/tests/test-prerequisites.sh"
"${project_dir}/tests/test-setup.sh"
"${project_dir}/tests/test-reauth.sh"
"${project_dir}/tests/test-setup-wizard-ui.sh"
"${project_dir}/tests/test-state.sh"
"${project_dir}/tests/test-ui-preferences.sh"
"${project_dir}/tests/test-ui-widgets.sh"
printf 'All repository checks passed.\n'
