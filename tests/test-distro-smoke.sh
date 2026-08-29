#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
expected_family="${1:-}"
test_root="$(mktemp -d /tmp/proton-drive-linux-distro-smoke.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

case "${expected_family}" in
    arch|debian) ;;
    *)
        printf 'Usage: test-distro-smoke.sh arch|debian\n' >&2
        exit 2
        ;;
esac

platform_json="$(PYTHONDONTWRITEBYTECODE=1 \
    python3 "${project_dir}/bin/pdrive-platform" --json)"
jq -e --arg family "${expected_family}" \
    '.family == $family and .automatic == true and (.packages | length) > 0' \
    >/dev/null <<< "${platform_json}"
mapfile -t runtime_packages < <(
    python3 "${project_dir}/bin/pdrive-platform" --packages
)
case "${expected_family}" in
    arch)
        for package in "${runtime_packages[@]}"; do
            pacman -Q -- "${package}" >/dev/null
        done
        ;;
    debian)
        for package in "${runtime_packages[@]}"; do
            dpkg-query -W -f='${db:Status-Abbrev}\n' "${package}" | grep -qx 'ii '
        done
        ;;
esac

mapfile -t shell_files < <(
    find "${project_dir}/bin" "${project_dir}/libexec" "${project_dir}/tests" \
        -maxdepth 1 -type f -name '*.sh' -print | sort
    printf '%s\n' "${project_dir}/install.sh" "${project_dir}/uninstall.sh"
)
for shell_file in "${shell_files[@]}"; do
    bash -n "${shell_file}"
done

for python_file in \
    "${project_dir}/bin/pdrive-desktop-gate" \
    "${project_dir}/bin/pdrive-platform" \
    "${project_dir}/bin/pdrive-state" \
    "${project_dir}/bin/pdrive-ui" \
    "${project_dir}/libexec/pdrive-draft-recovery-auto" \
    "${project_dir}/tests/test-draft-recovery.py"; do
    PYTHONDONTWRITEBYTECODE=1 python3 - "${python_file}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY
done

desktop-file-validate \
    "${project_dir}/share/applications/io.github.claudiuschuster.PDriveControl.desktop"
"${project_dir}/tests/test-platforms.sh"
HOME="${test_root}/platform-help" \
    python3 "${project_dir}/bin/pdrive-platform" --help >/dev/null
HOME="${test_root}/ui-help" \
    python3 "${project_dir}/bin/pdrive-ui" --help >/dev/null
"${project_dir}/tests/test-prerequisites.sh"
NO_AT_BRIDGE=1 "${project_dir}/tests/test-setup-wizard-ui.sh"
NO_AT_BRIDGE=1 xvfb-run -a python3 "${project_dir}/bin/pdrive-ui" --check
NO_AT_BRIDGE=1 xvfb-run -a python3 "${project_dir}/bin/pdrive-desktop-gate" --json \
    | jq -e '.schema_version == 1 and (.results | length) > 0' >/dev/null

printf 'PDrive %s-family container smoke checks passed.\n' "${expected_family}"
