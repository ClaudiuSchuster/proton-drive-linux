#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-cache-age.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
mkdir -p -- "${test_home}"

status_output="$(HOME="${test_home}" "${project_dir}/bin/pdrive-cache-age")"
grep -qF 'Saved:         24 hours' <<< "${status_output}"
[[ ! -e "${test_home}/.config/pdrive-cache.conf" ]]

HOME="${test_home}" "${project_dir}/bin/pdrive-cache-age" 72 >/dev/null
grep -qxF 'cache_max_age_hours=72' "${test_home}/.config/pdrive-cache.conf"
[[ "$(stat -c '%a' "${test_home}/.config/pdrive-cache.conf")" == 600 ]]

before="$(sha256sum "${test_home}/.config/pdrive-cache.conf")"
if HOME="${test_home}" "${project_dir}/bin/pdrive-cache-age" 0 >/dev/null 2>&1; then
    printf 'An invalid zero-hour cache age was accepted.\n' >&2
    exit 1
fi
after="$(sha256sum "${test_home}/.config/pdrive-cache.conf")"
[[ "${before}" == "${after}" ]]

if HOME="${test_home}" "${project_dir}/bin/pdrive-cache-age" 999999999999999999999 >/dev/null 2>&1; then
    printf 'An oversized cache age was accepted.\n' >&2
    exit 1
fi
after="$(sha256sum "${test_home}/.config/pdrive-cache.conf")"
[[ "${before}" == "${after}" ]]

HOME="${test_home}" "${project_dir}/bin/pdrive-cache-age" default >/dev/null
grep -qxF 'cache_max_age_hours=24' "${test_home}/.config/pdrive-cache.conf"

printf 'PDrive cache-retention checks passed.\n'
