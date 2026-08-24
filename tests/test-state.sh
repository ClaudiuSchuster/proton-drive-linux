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
    'EOF' > "${fake_bin}/systemctl"
printf '%s\n' \
    '#!/usr/bin/env bash' \
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
    'endpoint="${@: -1}"' \
    'if [[ "${PDRIVE_TEST_NO_VFS:-}" == 1 && "${endpoint}" == vfs/* ]]; then exit 99; fi' \
    'case "${endpoint}" in' \
    '  core/stats) printf "%s\\n" '\''{"bytes":1048576,"speed":524288,"errors":0,"transferring":[{"name":"demo/file.iso","size":2097152,"bytes":1048576,"speed":524288,"eta":2}]} '\'' ;;' \
    '  core/transferred) printf "%s\\n" '\''{"transferred":[{"name":"done.txt","size":12,"bytes":12,"completedAt":"2026-08-24T10:00:00+02:00"}]} '\'' ;;' \
    '  vfs/queue) printf "%s\\n" '\''{"queue":[{"name":"demo/file.iso","size":2097152,"tries":1,"uploading":true}]} '\'' ;;' \
    '  vfs/stats) printf "%s\\n" '\''{"diskCache":{"bytesUsed":3145728,"files":2,"uploadsQueued":1,"uploadsInProgress":1,"erroredFiles":0,"outOfSpace":false},"opt":{"CacheMaxAge":86400000000000}}'\'' ;;' \
    '  core/bwlimit) printf "%s\\n" '\''{"rate":"4M:off","bytesPerSecondTx":4194304}'\'' ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone-bin"
chmod 0755 "${fake_bin}/systemctl" "${fake_bin}/ss" \
    "${fake_bin}/findmnt" "${fake_bin}/rclone-bin"
touch "${state_dir}/pdrive-rc.sock"

cat > "${state_dir}/pdrive-watch-latest.txt" <<'EOF'
Zeit=2026-08-24T10:00:00+02:00
Status=ready
Grundcode=mounted
Grund=Proton Drive ist gemountet und bereit.
Hinweis=Der Mount ist nutzbar.
DNS=ok
TCP=established
FehlerImLog=7
HinweiseImLog=3
DeltaFehler=+0
DeltaHinweise=+0
MetadatenCacheLaufend=true
UploadslotsLaufend=4
CooldownDauerSekunden=43200
EOF
cat > "${state_dir}/proton-mount.log" <<'EOF'
2026/08/24 09:57:58 ERROR : rc: "vfs/queue": error: no VFS active and "fs" parameter not supplied
2026/08/24 09:58:00 NOTICE: proton drive root link ID 'private-share': 422 POST https://drive-api.proton.me/drive/shares/private-share/files?token=private: A file already exists
2026/08/24 09:59:00 ERROR : Projects/demo.qcow2: vfs cache: failed to upload try #4, will retry in 5m0s
EOF
printf '%s\n' \
    '2026-08-24T10:00:00+02:00 status=ready reason=mounted service=active/running pid=4242 mount=ready dns=ok tcp=established progress=yes success=1 queued=1 errors=7 notices=3 vfs_queue=1 vfs_queue_bytes=2097152 vfs_uploading=1 vfs_failed=0' \
    | tr ' ' '\t' > "${state_dir}/pdrive-watch-history.log"
printf '%s\n' 'bwlimit=4M:off' > "${config_dir}/pdrive-bwlimit.conf"
printf '%s\n' 'cache_max_age_hours=24' > "${config_dir}/pdrive-cache.conf"
printf '%s\n' 'transfers=4' > "${config_dir}/pdrive-transfers.conf"
printf '%s\n' 'proton_metadata_cache=true' > "${config_dir}/pdrive-recovery.conf"

state_json="${test_root}/state.json"
HOME="${test_home}" \
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
    and .service.pid == 4242
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
    and .queue.count == 1
    and .queue.active == 1
    and .vfs.cache_bytes == 3145728
    and .vfs.cache_state == "pending"
    and .vfs.clean_files == 1
    and .vfs.pending_files == 1
    and .bandwidth.live == "4M:off"
    and .configuration.metadata_cache == true
    and .configuration.cache_max_age_seconds == 86400
    and .configuration.running_cache_max_age_seconds == 86400
    and .configuration.cache_max_age_valid == true
    and .watchdog.summary == "Proton Drive is mounted and ready."
    and .watchdog.hint == "Run pdrive-watch for a detailed local diagnosis."
    and .issues.available == true
    and (.issues.events | length) == 3
    and .issues.events[0].category == "vfs-startup"
    and .issues.events[1].category == "http-422"
    and (.issues.events[1].subject | contains("private-share") | not)
    and (.issues.events[1].message | contains("private-share") | not)
    and (.issues.events[1].message | contains("<Proton API URL>"))
    and .issues.events[2].category == "upload-retry"
    and .history[0].vfs_queue == 1
' "${state_json}" >/dev/null

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

printf 'pdrive-state fixture checks passed.\n'
