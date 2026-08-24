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
    'printf "%s\\n" "/tmp/pdrive proton-test: fuse.rclone rw,nosuid,nodev"' \
    > "${fake_bin}/findmnt"
# These single-quoted lines deliberately write literal shell expansions into
# the fake rclone executable instead of expanding them in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'endpoint="${@: -1}"' \
    'case "${endpoint}" in' \
    '  core/stats) printf "%s\\n" '\''{"bytes":1048576,"speed":524288,"errors":0,"transferring":[{"name":"demo/file.iso","size":2097152,"bytes":1048576,"speed":524288,"eta":2}]} '\'' ;;' \
    '  core/transferred) printf "%s\\n" '\''{"transferred":[{"name":"done.txt","size":12,"bytes":12,"completedAt":"2026-08-24T10:00:00+02:00"}]} '\'' ;;' \
    '  vfs/queue) printf "%s\\n" '\''{"queue":[{"name":"demo/file.iso","size":2097152,"tries":1,"uploading":true}]} '\'' ;;' \
    '  vfs/stats) printf "%s\\n" '\''{"diskCache":{"bytesUsed":3145728,"files":2,"uploadsQueued":1,"uploadsInProgress":1,"erroredFiles":0,"outOfSpace":false}}'\'' ;;' \
    '  core/bwlimit) printf "%s\\n" '\''{"rate":"4M:off","bytesPerSecondTx":4194304}'\'' ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_bin}/rclone-bin"
chmod 0755 "${fake_bin}/systemctl" "${fake_bin}/findmnt" "${fake_bin}/rclone-bin"
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
printf '%s\n' \
    '2026-08-24T10:00:00+02:00 status=ready reason=mounted service=active/running pid=4242 mount=ready dns=ok tcp=established progress=yes success=1 queued=1 errors=7 notices=3 vfs_queue=1 vfs_queue_bytes=2097152 vfs_uploading=1 vfs_failed=0' \
    | tr ' ' '\t' > "${state_dir}/pdrive-watch-history.log"
printf '%s\n' 'bwlimit=4M:off' > "${config_dir}/pdrive-bwlimit.conf"
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
    "${project_dir}/bin/pdrive-state" --compact > "${state_json}"

jq -e '
    .schema_version == 1
    and .health.status == "ready"
    and .service.pid == 4242
    and .mount.ready == true
    and .stats.speed == 524288
    and .transfers.active[0].name == "demo/file.iso"
    and .queue.count == 1
    and .queue.active == 1
    and .vfs.cache_bytes == 3145728
    and .bandwidth.live == "4M:off"
    and .configuration.metadata_cache == true
    and .history[0].vfs_queue == 1
' "${state_json}" >/dev/null

printf 'pdrive-state fixture checks passed.\n'
