#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-auth-guard.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

fake_bin="${test_root}/bin"
state_dir="${test_root}/state"
mount_log="${state_dir}/mount.log"
events="${test_root}/events.log"
preferences="${test_root}/pdrive-ui.json"
mkdir -p -- "${fake_bin}" "${state_dir}"
: > "${mount_log}"
: > "${events}"

# Keep fixture expansions literal until the fake command runs.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "systemctl:%s\n" "$*" >> "${PDRIVE_TEST_EVENTS}"' \
    'exit 0' > "${fake_bin}/systemctl"
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "notify-send:%s\n" "$*" >> "${PDRIVE_TEST_EVENTS}"' \
    'exit 0' > "${fake_bin}/notify-send"
chmod 0755 "${fake_bin}/systemctl" "${fake_bin}/notify-send"

cat > "${preferences}" <<'EOF'
{
  "language": "de",
  "notification_policy": "important"
}
EOF

run_guard() {
    HOME="${test_root}/home" \
        PATH="${fake_bin}:/usr/bin:/bin" \
        PDRIVE_STATE_DIR="${state_dir}" \
        PDRIVE_MOUNT_LOG="${mount_log}" \
        PDRIVE_UI_PREFERENCES="${preferences}" \
        PDRIVE_AUTH_RATE_LIMIT_SECONDS=120 \
        PDRIVE_TEST_EVENTS="${events}" \
        "${project_dir}/libexec/pdrive-auth-failure-guard" "$@"
}

run_guard --begin-start
printf '%s\n' \
    "2026/08/27 00:20:31 CRITICAL: Failed to create file system: 503 Service Unavailable" \
    >> "${mount_log}"
run_guard --after-service-exit
[[ ! -e "${state_dir}/pdrive-auth-state.json" ]]
[[ ! -s "${events}" ]]
run_guard --start-allowed

run_guard --begin-start
printf '%s\n' \
    "2026/08/27 02:21:18 CRITICAL: Failed to create file system: this account requires a 2FA code. Can be provided with --protondrive-2fa=000000" \
    >> "${mount_log}"
run_guard --after-service-exit
jq -e '
  .schema_version == 1
  and .status == "reauthorization-required"
  and .reason == "two-factor-required"
  and .restart_suppressed == true
' "${state_dir}/pdrive-auth-state.json" >/dev/null
[[ "$(stat -c %a "${state_dir}/pdrive-auth-state.json")" == 600 ]]
grep -qF 'systemctl:--user --no-block stop rclone-proton-drive.service' "${events}"
grep -qF 'PDrive muss neu autorisiert werden' "${events}"
if run_guard --start-allowed 2> "${test_root}/blocked-start"; then
    printf 'A terminal authentication state allowed a direct service start.\n' >&2
    exit 1
fi
grep -qF 'requires attention' "${test_root}/blocked-start"

notification_count="$(grep -c '^notify-send:' "${events}")"
run_guard --after-service-exit
[[ "$(grep -c '^notify-send:' "${events}")" == "${notification_count}" ]]
[[ "$(grep -c '^systemctl:' "${events}")" == 2 ]]

run_guard --mark-healthy
jq -e '
  .status == "ready"
  and .reason == "authenticated"
  and .restart_suppressed == false
' "${state_dir}/pdrive-auth-state.json" >/dev/null
run_guard --start-allowed

rate_limit_started="$(date +%s)"
run_guard --mark-rate-limited
jq -e '
  .status == "rate-limited"
  and .reason == "login-rate-limited"
  and .restart_suppressed == true
  and (.retry_after | type == "string")
' "${state_dir}/pdrive-auth-state.json" >/dev/null
retry_epoch="$(date --date="$(jq -r .retry_after "${state_dir}/pdrive-auth-state.json")" +%s)"
(( retry_epoch >= rate_limit_started + 119 ))
(( retry_epoch <= rate_limit_started + 121 ))
rate_limited_state="$(sha256sum "${state_dir}/pdrive-auth-state.json")"
if run_guard --start-allowed 2> "${test_root}/rate-limited-start"; then
    printf 'A rate-limited authentication state allowed a direct service start.\n' >&2
    exit 1
fi
[[ "$(sha256sum "${state_dir}/pdrive-auth-state.json")" == "${rate_limited_state}" ]]

printf '%s\n' '{not valid json' > "${state_dir}/pdrive-auth-state.json"
if run_guard --start-allowed 2> "${test_root}/malformed-start"; then
    printf 'A malformed authentication state allowed a direct service start.\n' >&2
    exit 1
fi
grep -qF 'malformed' "${test_root}/malformed-start"

run_guard >/dev/null
run_guard --help >/dev/null
printf 'PDrive authentication failure guard checks passed.\n'
