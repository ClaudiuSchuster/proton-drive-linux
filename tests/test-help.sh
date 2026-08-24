#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-help.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
mkdir -p "${test_home}/.local/libexec"
install -m 0755 "${project_dir}/libexec/setup-rclone-proton" \
    "${test_home}/.local/libexec/setup-rclone-proton"

snapshot() {
    find "${test_home}" -mindepth 1 -printf '%P|%y|%s\n' | sort
}

before="$(snapshot)"
for helper in pdrive-bwlimit pdrive-cache-age pdrive-doctor pdrive-draft-recovery pdrive-reauth \
    pdrive-prerequisites pdrive-recovery pdrive-refresh pdrive-setup pdrive-state pdrive-transfers \
    pdrive-ui pdrive-watch; do
    HOME="${test_home}" "${project_dir}/bin/${helper}" --help >/dev/null
done
watch_help="$(HOME="${test_home}" "${project_dir}/bin/pdrive-watch" --help)"
grep -qF 'RESTART' <<< "${watch_help}"
if grep -qF 'NEUSTART' <<< "${watch_help}"; then
    printf 'The public restart confirmation is not English-first.\n' >&2
    exit 1
fi
HOME="${test_home}" bash "${project_dir}/install.sh" --help >/dev/null
HOME="${test_home}" bash "${project_dir}/uninstall.sh" --help >/dev/null
HOME="${test_home}" bash "${project_dir}/libexec/setup-rclone-proton" >/dev/null
after="$(snapshot)"

if [[ "${before}" != "${after}" ]]; then
    printf 'A documented help path changed the test HOME.\n' >&2
    diff -u <(printf '%s\n' "${before}") <(printf '%s\n' "${after}") >&2 || true
    exit 1
fi

printf 'Action-free help checks passed.\n'
