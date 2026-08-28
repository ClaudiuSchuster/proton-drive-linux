#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-state.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
fake_bin="${test_root}/bin"
state_dir="${test_home}/.local/state/rclone"
config_dir="${test_home}/.config"
mkdir -p -- "${fake_bin}" "${state_dir}" "${config_dir}" "${test_root}/mount"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'cat <<EOF' \
    'ActiveState=active' \
    'SubState=running' \
    'MainPID=4242' \
    'Result=success' \
    'ExecMainStatus=0' \
    'NRestarts=0' \
    'ActiveEnterTimestamp=Mon 2026-08-24 10:00:00 CEST' \
    'ActiveEnterTimestampMonotonic=1000000' \
    'EOF' > "${fake_bin}/systemctl"
# This single-quoted line deliberately writes a literal shell expansion into
# the fake ss executable instead of expanding it in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${PDRIVE_TEST_NO_TCP:-}" == 1 ]]; then exit 0; fi' \
    'cat <<EOF' \
    '0 0 192.0.2.10:54321 198.51.100.20:443 users:(("rclone-bin",pid=4242,fd=8))' \
    ' cubic bytes_sent:8388608 bytes_acked:8388609 bytes_received:3145728' \
    '0 0 192.0.2.10:54322 198.51.100.21:443 users:(("unrelated",pid=5151,fd=9))' \
    ' cubic bytes_sent:999999999 bytes_received:999999999' \
    'EOF' > "${fake_bin}/ss"
# This single-quoted line deliberately writes a literal shell expansion into
# the fake findmnt executable instead of expanding it in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${PDRIVE_TEST_NO_MOUNT:-}" == 1 ]]; then exit 1; fi' \
    'printf "%s\\n" "/tmp/pdrive proton-test: fuse.rclone rw,nosuid,nodev"' \
    > "${fake_bin}/findmnt"
# These single-quoted lines deliberately write literal shell expansions into
# the fake rclone executable instead of expanding them in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'endpoint=""' \
    'for argument in "$@"; do' \
    '  case "${argument}" in core/*|vfs/*|backend/*) endpoint="${argument}" ;; esac' \
    'done' \
    'if [[ "${PDRIVE_TEST_NO_VFS:-}" == 1 && "${endpoint}" == vfs/* ]]; then exit 99; fi' \
    'case "${endpoint}" in' \
    '  core/stats)' \
    '    if [[ "${PDRIVE_TEST_STALLED:-}" == 1 ]]; then' \
    '      printf "%s\n" '\''{"bytes":1048576,"speed":0,"errors":0,"transferring":[{"name":"demo/file.iso","size":2097152,"bytes":1048576,"speed":0,"eta":null}]} '\''' \
    '    elif [[ "${PDRIVE_TEST_COMPLETE:-}" == 1 ]]; then' \
    '      printf "%s\\n" '\''{"bytes":2097152,"speed":0,"errors":0,"transferring":[{"name":"demo/file.iso","size":2097152,"bytes":2097152,"speed":0,"eta":null}]} '\''' \
    '    else' \
    '      printf "%s\\n" '\''{"bytes":1048576,"speed":524288,"errors":0,"transferring":[{"name":"demo/file.iso","size":2097152,"bytes":1048576,"speed":524288,"eta":2}]} '\''' \
    '    fi ;;' \
    '  core/transferred) printf "%s\\n" '\''{"transferred":[{"name":"done.txt","size":12,"bytes":12,"completedAt":"2026-08-24T10:00:00+00:00","srcFs":"/tmp/vfs/proton-test","dstFs":"proton-test:"},{"name":"Projects/demo.qcow2","size":1048576,"bytes":1048576,"completedAt":"2026-08-24T10:04:00+00:00","srcFs":"proton-test:","dstFs":"/tmp/vfs/proton-test"},{"name":"missing-direction.txt","size":24,"bytes":24,"completedAt":"2026-08-24T10:05:00+00:00"},{"name":"ambiguous-direction.txt","size":48,"bytes":48,"completedAt":"2026-08-24T10:06:00+00:00","srcFs":"proton-test:source","dstFs":"proton-test:destination"}]} '\'' ;;' \
    '  vfs/queue) printf "%s\\n" '\''{"queue":[{"name":"demo/file.iso","size":2097152,"tries":2,"uploading":true}]} '\'' ;;' \
    '  vfs/stats) printf "%s\\n" '\''{"diskCache":{"bytesUsed":3145728,"files":2,"uploadsQueued":1,"uploadsInProgress":1,"erroredFiles":0,"outOfSpace":false},"opt":{"CacheMaxAge":86400000000000}}'\'' ;;' \
    '  backend/command) printf "%s\\n" '\''{"result":{"upload":"4M","download":"2M","uploadBytesPerSecond":4194304,"downloadBytesPerSecond":2097152}}'\'' ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone-bin"
chmod 0755 "${fake_bin}/systemctl" "${fake_bin}/ss" \
    "${fake_bin}/findmnt" "${fake_bin}/rclone-bin"
touch "${state_dir}/pdrive-rc.sock"

cat > "${state_dir}/pdrive-watch-latest.txt" <<'EOF'
generated_at=2026-08-24T10:08:00+00:00
status=ready
reason_code=mounted
reason=Proton Drive is mounted and ready.
hint=The mount is ready for use.
dns=ok
tcp=established
errors_in_log=7
notices_in_log=3
delta_errors=+0
delta_notices=+0
metadata_cache_running=true
upload_slots_running=4
cooldown_seconds=43200
EOF
cat > "${state_dir}/pdrive-draft-recovery-latest.json" <<'EOF'
{
  "detail": "One guarded recovery restart restored the protected queue.",
  "error_category": "remote-file-removed",
  "generated_at": "2026-08-24T10:08:30+00:00",
  "phase": "recovery",
  "progress_proven": true,
  "queue_count": 1,
  "bridge_failure_cycles": 3,
  "bridge_unwedge_restart_attempts": 1,
  "finalization_restart_attempts": 0,
  "restart_attempts": 2,
  "stall_confirmations": 2,
  "status": "restarted"
}
EOF
cat > "${state_dir}/pdrive-auth-state.json" <<'EOF'
{
  "generated_at": "2026-08-24T10:08:45+00:00",
  "reason": "authenticated",
  "restart_suppressed": false,
  "schema_version": 1,
  "status": "ready"
}
EOF
cat > "${state_dir}/proton-mount.log" <<'EOF'
2026/08/24 09:54:00 ERROR : Failed to create file system for "proton:": couldn't initialize a new proton drive instance: 503 POST https://drive-api.proton.me/auth 503 Service Unavailable (Code=0, Status=503)
2026/08/24 09:57:58 ERROR : rc: "vfs/queue": error: no VFS active and "fs" parameter not supplied
2026/08/24 09:58:00 NOTICE: proton drive root link ID 'private-share': 422 POST https://drive-api.proton.me/drive/shares/private-share/files?token=private: A file already exists
2026/08/24 09:58:00 ERROR : Projects/demo.qcow2: a draft exist - usually this means a failed upload attempt
2026/08/24 09:58:00 ERROR : Projects/demo.qcow2: vfs cache: failed to upload try #4, will retry in 5m0s
2026/08/24 10:03:00 NOTICE: proton drive root link ID 'private-share': 422 POST https://drive-api.proton.me/drive/shares/private-share/files?token=private: A file already exists
2026/08/24 10:03:00 ERROR : Projects/demo.qcow2: a draft exist - usually this means a failed upload attempt
2026/08/24 10:03:00 ERROR : Projects/demo.qcow2: vfs cache: failed to upload try #5, will retry in 5m0s
2026/08/24 09:55:00 ERROR : unrelated backend failure
2026/08/24 10:05:00 NOTICE: Bandwidth limit set to {235.520Ki off}
2026/08/24 10:05:01 NOTICE: Bandwidth limit reset to unlimited
2026/08/24 10:05:30 ERROR : Proton events: 503 POST https://drive-api.proton.me/drive/events 503 Service Unavailable (Code=0, Status=503)
2026/08/24 10:06:00 ERROR : demo/file.iso: vfs cache: failed to upload try #2, will retry in 5m0s
2026/08/24 10:06:10 ERROR : Another/file.bin: a draft exist - usually this means a failed upload attempt
2026/08/24 10:06:11 ERROR : Another/file.bin: vfs cache: failed to upload try #3, will retry in 5m0s
2026/08/24 10:06:30 ERROR : proton drive root link ID 'private-share': 502 POST https://storage.proton.me/storage/blocks 502 Bad Gateway (Code=0, Status=502)
2026/08/24 10:07:00 ERROR : dial tcp: lookup drive-api.proton.me: temporary failure in name resolution
EOF
printf '%s\n' \
    '2026-08-24T10:00:00+00:00 status=ready reason=mounted service=active/running pid=4242 mount=ready dns=ok tcp=established progress=yes success=1 queued=1 errors=7 notices=3 vfs_queue=1 vfs_queue_bytes=2097152 vfs_uploading=1 vfs_failed=0' \
    | tr ' ' '\t' > "${state_dir}/pdrive-watch-history.log"
printf '%s\n' 'bwlimit=4M:2M' > "${config_dir}/pdrive-bwlimit.conf"
printf '%s\n' 'cache_max_age_hours=24' > "${config_dir}/pdrive-cache.conf"
printf '%s\n' 'transfers=4' > "${config_dir}/pdrive-transfers.conf"
printf '%s\n' 'proton_metadata_cache=true' > "${config_dir}/pdrive-recovery.conf"

state_json="${test_root}/state.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact --include-capacity > "${state_json}"

jq -e '
    .schema_version == 1
    and .health.status == "ready"
    and .authentication.available == true
    and .authentication.status == "ready"
    and .authentication.reason == "authenticated"
    and .authentication.restart_suppressed == false
    and .service.pid == 4242
    and .service.uptime_seconds >= 0
    and .network_io.available == true
    and .network_io.connections == 1
    and .network_io.sent_bytes == 8388608
    and .network_io.received_bytes == 3145728
    and .remote_capacity.available == true
    and .remote_capacity.total_bytes > 0
    and .remote_capacity.used_bytes >= 0
    and .remote_capacity.free_bytes > 0
    and .mount.ready == true
    and .stats.speed == 524288
    and .transfers.active[0].name == "demo/file.iso"
    and .transfers.active[0].direction == "unknown"
    and ([.transfers.recent[].direction] == ["upload", "download", "unknown", "unknown"])
    and ([.transfers.recent[] | has("srcFs") or has("dstFs")] | any | not)
    and .queue.count == 1
    and .queue.active == 1
    and .queue.remaining_bytes == 1048576
    and .vfs.cache_bytes == 3145728
    and .vfs.cache_state == "pending"
    and .vfs.clean_files == 1
    and .vfs.pending_files == 1
    and .bandwidth.configured == "4M:2M"
    and .bandwidth.live == "4M:2M"
    and .bandwidth.upload_bytes_per_second == 4194304
    and .bandwidth.download_bytes_per_second == 2097152
    and .configuration.metadata_cache == true
    and .configuration.cache_max_age_seconds == 86400
    and .configuration.running_cache_max_age_seconds == 86400
    and .configuration.cache_max_age_valid == true
    and .watchdog.summary == "Proton Drive is mounted and ready."
    and .watchdog.hint == "Run pdrive-watch for a detailed local diagnosis."
    and .draft_recovery.available == true
    and .draft_recovery.status == "restarted"
    and .draft_recovery.phase == "recovery"
    and .draft_recovery.progress_proven == true
    and .draft_recovery.error_category == "remote-file-removed"
    and .draft_recovery.stall_confirmations == 2
    and .draft_recovery.restart_attempts == 2
    and .draft_recovery.finalization_restart_attempts == 0
    and .draft_recovery.bridge_unwedge_restart_attempts == 1
    and .draft_recovery.bridge_failure_cycles == 3
    and .issues.available == true
    and (.issues.events | length) == 8
    and .issues.events[0].category == "dns"
    and .issues.events[0].lifecycle == "resolved"
    and .issues.events[0].title == "Network resolution recovered"
    and .issues.events[1].subject == "proton drive root link ID '\''<redacted>'\''"
    and .issues.events[1].category == "http-5xx"
    and .issues.events[1].level == "notice"
    and .issues.events[1].lifecycle == "recovering"
    and .issues.events[1].title == "Upload retry is progressing"
    and .issues.events[2].subject == "Another/file.bin"
    and .issues.events[2].category == "draft-conflict"
    and .issues.events[2].lifecycle == "active"
    and .issues.events[2].raw_events == 2
    and .issues.events[3].category == "upload-retry"
    and .issues.events[3].level == "notice"
    and .issues.events[3].lifecycle == "recovering"
    and .issues.events[3].title == "Upload retry is progressing"
    and .issues.events[4].category == "http-5xx"
    and .issues.events[4].subject == "Proton events"
    and .issues.events[4].level == "error"
    and .issues.events[4].lifecycle == "active"
    and .issues.events[5].category == "draft-conflict"
    and .issues.events[5].level == "notice"
    and .issues.events[5].lifecycle == "resolved"
    and .issues.events[5].title == "Upload recovered automatically"
    and .issues.events[5].resolved_at == "2026-08-24T10:04:00+00:00"
    and .issues.events[5].occurrences == 2
    and .issues.events[5].raw_events == 6
    and .issues.events[6].message == "unrelated backend failure"
    and .issues.events[6].lifecycle == "active"
    and .issues.events[7].category == "http-5xx"
    and .issues.events[7].level == "notice"
    and .issues.events[7].lifecycle == "resolved"
    and .issues.events[7].title == "Proton service recovered"
    and .issues.events[7].resolved_at == "2026-08-24T10:08:45+00:00"
    and .issues.events[0].last_seen > .issues.events[1].last_seen
    and .issues.events[1].last_seen > .issues.events[2].last_seen
    and .issues.events[2].last_seen > .issues.events[3].last_seen
    and .issues.events[3].last_seen > .issues.events[4].last_seen
    and .issues.events[4].last_seen > .issues.events[5].last_seen
    and .issues.events[5].last_seen > .issues.events[6].last_seen
    and .issues.events[6].last_seen > .issues.events[7].last_seen
    and .issues.raw_events == 15
    and .issues.errors == 3
    and .issues.notices == 2
    and .issues.active == 3
    and .issues.recovering == 2
    and .issues.resolved == 3
    and (.issues.events[1].subject | contains("private-share") | not)
    and (.issues.events[5].subject | contains("private-share") | not)
    and (.issues.events[5].message | contains("private-share") | not)
    and .history[0].vfs_queue == 1
' "${state_json}" >/dev/null

cp -- "${state_dir}/pdrive-watch-latest.txt" "${state_dir}/pdrive-watch-latest.ready"
cat > "${state_dir}/pdrive-watch-latest.txt" <<'EOF'
Zeit=2026-08-24T10:08:00+00:00
Modus=Timer-Aufzeichnung
Status=warning
Grundcode=stale-log
DNS=ok
TCP=established
FehlerImLog=9
HinweiseImLog=4
LetzteProblemkategorie=Hinweis
EOF
legacy_watchdog_json="${test_root}/legacy-watchdog.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${legacy_watchdog_json}"
jq -e '
    .watchdog.mode == "timer-record"
    and .watchdog.status == "warning"
    and .watchdog.reason_code == "stale-log"
    and .watchdog.errors == 9
    and .watchdog.notices == 4
    and .watchdog.last_problem_category == "notice"
' "${legacy_watchdog_json}" >/dev/null
mv -f -- "${state_dir}/pdrive-watch-latest.ready" \
    "${state_dir}/pdrive-watch-latest.txt"

cp -- "${state_dir}/pdrive-watch-latest.txt" "${state_dir}/pdrive-watch-latest.ready"
sed -i \
    -e "s|^generated_at=.*|generated_at=$(date --iso-8601=seconds)|" \
    -e 's/^status=ready$/status=critical/' \
    -e 's/^reason_code=mounted$/reason_code=service-down/' \
    "${state_dir}/pdrive-watch-latest.txt"
stale_watchdog_json="${test_root}/stale-watchdog.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${stale_watchdog_json}"
jq -e '
    .service.active == true
    and .mount.ready == true
    and .watchdog.status == "critical"
    and .watchdog.reason_code == "service-down"
    and .health.status == "ready"
    and .health.reason_code == "mounted"
' "${stale_watchdog_json}" >/dev/null
mv -f -- "${state_dir}/pdrive-watch-latest.ready" \
    "${state_dir}/pdrive-watch-latest.txt"

cp -- "${state_dir}/pdrive-draft-recovery-latest.json" \
    "${state_dir}/pdrive-draft-recovery-latest.ready"
cat > "${state_dir}/pdrive-draft-recovery-latest.json" <<EOF
{
  "detail": "The guarded restart limit for this cache generation has been reached.",
  "error_category": "remote-file-removed",
  "generated_at": "$(date --iso-8601=seconds)",
  "phase": "recovery",
  "progress_proven": true,
  "queue_count": 1,
  "restart_attempts": 2,
  "status": "restart-limited"
}
EOF
recovery_limited_json="${test_root}/recovery-limited.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_TEST_NO_TCP=1 \
PDRIVE_TEST_STALLED=1 \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${recovery_limited_json}"
jq -e '
    .health.status == "warning"
    and .health.reason_code == "recovery-limited"
    and (.health.summary | contains("Local cache data remains protected"))
    and .network_io.available == true
    and .network_io.connections == 0
    and .stats.speed == 0
    and .queue.count == 1
' "${recovery_limited_json}" >/dev/null
mv -f -- "${state_dir}/pdrive-draft-recovery-latest.ready" \
    "${state_dir}/pdrive-draft-recovery-latest.json"

finalizing_json="${test_root}/state-finalizing.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_TEST_COMPLETE=1 \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${finalizing_json}"

jq -e '
    .health.summary == "Proton is finalizing 1 fully transferred upload(s)."
    and .queue.finalizing == 1
    and .queue.remaining_bytes == 0
    and .queue.items[0].stage == "finalizing"
    and .transfers.active[0].stage == "finalizing"
' "${finalizing_json}" >/dev/null

startup_json="${test_root}/startup.json"
HOME="${test_home}" \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
PDRIVE_TEST_NO_MOUNT=1 \
PDRIVE_TEST_NO_VFS=1 \
    "${project_dir}/bin/pdrive-state" --compact > "${startup_json}"

jq -e '
    .health.reason_code == "mount-not-ready"
    and .mount.ready == false
    and .remote_capacity.available == false
    and .vfs.available == false
    and ([.health.components[].component | select(startswith("vfs/"))] | length) == 0
' "${startup_json}" >/dev/null

cat > "${state_dir}/pdrive-auth-state.json" <<'EOF'
{
  "generated_at": "2026-08-24T10:09:00+00:00",
  "reason": "two-factor-required",
  "restart_suppressed": true,
  "schema_version": 1,
  "status": "reauthorization-required"
}
EOF
auth_json="${test_root}/auth-required.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${auth_json}"

jq -e '
    .health.status == "critical"
    and .health.reason_code == "reauthorization-required"
    and (.health.summary | contains("Automatic login retries were stopped"))
    and .authentication.status == "reauthorization-required"
    and .authentication.reason == "two-factor-required"
    and .authentication.restart_suppressed == true
' "${auth_json}" >/dev/null

cat > "${state_dir}/pdrive-auth-state.json" <<'EOF'
{
  "generated_at": "2026-08-24T10:10:00+00:00",
  "reason": "login-rate-limited",
  "restart_suppressed": true,
  "retry_after": "2099-08-24T11:10:00+00:00",
  "schema_version": 1,
  "status": "rate-limited"
}
EOF
rate_limited_json="${test_root}/auth-rate-limited.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${rate_limited_json}"

jq -e '
    .health.status == "critical"
    and .health.reason_code == "reauthorization-rate-limited"
    and (.health.summary | contains("cooldown expires"))
    and .authentication.status == "rate-limited"
    and .authentication.reason == "login-rate-limited"
    and .authentication.retry_remaining_seconds > 0
    and .authentication.restart_suppressed == true
' "${rate_limited_json}" >/dev/null

jq 'del(.retry_after)' "${state_dir}/pdrive-auth-state.json" \
    > "${state_dir}/pdrive-auth-state.malformed.json"
mv -f -- "${state_dir}/pdrive-auth-state.malformed.json" \
    "${state_dir}/pdrive-auth-state.json"
malformed_rate_limit_json="${test_root}/auth-rate-limit-malformed.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${malformed_rate_limit_json}"

jq -e '
    .health.reason_code == "reauthorization-rate-limited"
    and .authentication.status == "rate-limited"
    and .authentication.retry_remaining_seconds == -1
' "${malformed_rate_limit_json}" >/dev/null

jq '.retry_after = "2020-08-24T11:10:00+00:00"' \
    "${state_dir}/pdrive-auth-state.json" > "${state_dir}/pdrive-auth-state.expired.json"
mv -f -- "${state_dir}/pdrive-auth-state.expired.json" \
    "${state_dir}/pdrive-auth-state.json"
expired_rate_limit_json="${test_root}/auth-rate-limit-expired.json"
HOME="${test_home}" \
TZ=UTC \
PATH="${fake_bin}:/usr/bin:/bin" \
PDRIVE_STATE_DIR="${state_dir}" \
PDRIVE_CONFIG_DIR="${config_dir}" \
PDRIVE_MOUNT_DIR="${test_root}/mount" \
PDRIVE_RC_SOCKET="${state_dir}/pdrive-rc.sock" \
PDRIVE_RCLONE_BIN="${fake_bin}/rclone-bin" \
PDRIVE_RC_TRANSPORT=cli \
    "${project_dir}/bin/pdrive-state" --compact > "${expired_rate_limit_json}"

jq -e '
    .health.reason_code == "reauthorization-required"
    and .authentication.status == "reauthorization-required"
    and .authentication.retry_remaining_seconds == 0
' "${expired_rate_limit_json}" >/dev/null

printf 'pdrive-state fixture checks passed.\n'
