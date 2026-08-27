#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-network-tune.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
fake_curl="${test_root}/curl"
mkdir -p -- "${test_home}"

cat > "${fake_curl}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
direction=download
for argument in "$@"; do
    if [[ "${argument}" == *'/__up?'* ]]; then
        direction=upload
    fi
done
if [[ "${direction}" == upload ]]; then
    dd of=/dev/null status=none
    printf '8388608'
else
    printf '20971520'
fi
EOF
chmod 0755 "${fake_curl}"

if HOME="${test_home}" PDRIVE_CURL_BIN="${fake_curl}" \
    "${project_dir}/bin/pdrive-network-tune" status >/dev/null 2>&1; then
    printf 'Network-tune status unexpectedly succeeded without a measurement.\n' >&2
    exit 1
fi

result="$({
    HOME="${test_home}" \
        PDRIVE_CURL_BIN="${fake_curl}" \
        PDRIVE_TUNE_PROVIDER_URL='https://speed.example.test' \
        "${project_dir}/bin/pdrive-network-tune" measure --json
})"

jq -e '
    .schema == 1
    and .provider == "https://speed.example.test"
    and .approximate_transferred_bytes == 72000000
    and .bulk_percent == 60
    and .reserve_percent == 40
    and .upload.measured_mib_per_second == 8
    and .upload.recommended_mib_per_second == 4.8
    and .download.measured_mib_per_second == 20
    and .download.recommended_mib_per_second == 12
' <<< "${result}" >/dev/null

result_file="${test_home}/.config/pdrive-network-tune.json"
[[ "$(stat -c %a -- "${result_file}")" == 600 ]]
cmp -s <(jq -S . <<< "${result}") <(jq -S . "${result_file}")

status_output="$(HOME="${test_home}" "${project_dir}/bin/pdrive-network-tune" status)"
grep -qF '4.80 MiB/s bulk limit' <<< "${status_output}"
grep -qF '12.00 MiB/s bulk limit' <<< "${status_output}"
grep -qF '40% for browsing and other traffic' <<< "${status_output}"

help_output="$(HOME="${test_home}" "${project_dir}/bin/pdrive-network-tune" --help)"
grep -qF 'About 72 MB' <<< "${help_output}"

printf 'PDrive network auto-tune checks passed.\n'
