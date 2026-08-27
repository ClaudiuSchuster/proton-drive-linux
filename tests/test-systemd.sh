#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
unit_dir="${project_dir}/systemd/user"
expected_units=(
    pdrive-draft-recovery.service
    pdrive-draft-recovery.timer
    pdrive-watch.service
    pdrive-watch.timer
    proton-drive-update.service
    proton-drive-update.timer
    rclone-proton-drive.service
    rclone-selfupdate.service
    rclone-selfupdate.timer
)

mapfile -t actual_units < <(find "${unit_dir}" -maxdepth 1 -type f \
    \( -name '*.service' -o -name '*.timer' \) -printf '%f\n' | sort)
if [[ "${actual_units[*]}" != "${expected_units[*]}" ]]; then
    printf 'Unexpected systemd user-unit inventory.\n' >&2
    printf 'Expected: %s\nActual:   %s\n' "${expected_units[*]}" "${actual_units[*]}" >&2
    exit 1
fi

for unit in "${expected_units[@]}"; do
    grep -qFx '[Unit]' "${unit_dir}/${unit}"
    grep -qE '^Description=.+$' "${unit_dir}/${unit}"
done

for service in pdrive-draft-recovery.service pdrive-watch.service proton-drive-update.service \
    rclone-proton-drive.service rclone-selfupdate.service; do
    grep -qFx 'UMask=0077' "${unit_dir}/${service}"
done

declare -A expected_exec_starts=(
    [pdrive-draft-recovery.service]='%h/.local/libexec/pdrive-draft-recovery-auto --auto'
    [pdrive-watch.service]='%h/.local/bin/pdrive-watch --record'
    [proton-drive-update.service]='%h/.local/libexec/proton-drive-update'
    [rclone-proton-drive.service]='%h/.local/libexec/rclone-proton-mount'
    [rclone-selfupdate.service]='%h/.local/libexec/rclone-selfupdate'
)
declare -A expected_sources=(
    [pdrive-draft-recovery.service]='libexec/pdrive-draft-recovery-auto'
    [pdrive-watch.service]='bin/pdrive-watch'
    [proton-drive-update.service]='libexec/proton-drive-update'
    [rclone-proton-drive.service]='libexec/rclone-proton-mount'
    [rclone-selfupdate.service]='libexec/rclone-selfupdate'
)
for service in "${!expected_exec_starts[@]}"; do
    grep -qFx "ExecStart=${expected_exec_starts[${service}]}" "${unit_dir}/${service}"
    [[ -x "${project_dir}/${expected_sources[${service}]}" ]]
done

mount_unit="${unit_dir}/rclone-proton-drive.service"
grep -qFx 'Type=notify' "${mount_unit}"
grep -qFx 'TimeoutStartSec=infinity' "${mount_unit}"
grep -qFx 'RestartSec=1h' "${mount_unit}"
grep -qFx 'ExecCondition=%h/.local/libexec/pdrive-auth-failure-guard --start-allowed' "${mount_unit}"
grep -qFx 'ExecStartPre=%h/.local/libexec/pdrive-auth-failure-guard --begin-start' "${mount_unit}"
grep -qFx 'ExecStartPost=%h/.local/bin/pdrive-bwlimit --apply-startup' "${mount_unit}"
grep -qFx 'ExecStartPost=%h/.local/libexec/pdrive-auth-failure-guard --mark-healthy' "${mount_unit}"
grep -qFx 'ExecStopPost=%h/.local/libexec/pdrive-auth-failure-guard --after-service-exit' "${mount_unit}"
[[ -x "${project_dir}/libexec/pdrive-auth-failure-guard" ]]
if grep -Eq '^(NoNewPrivileges|PrivateDevices|PrivateMounts|ProtectHome)=' "${mount_unit}"; then
    printf 'The FUSE/Keyring mount unit gained incompatible generic sandboxing.\n' >&2
    exit 1
fi

for service in pdrive-draft-recovery.service pdrive-watch.service proton-drive-update.service \
    rclone-selfupdate.service; do
    grep -qFx 'Type=oneshot' "${unit_dir}/${service}"
    grep -qFx 'NoNewPrivileges=true' "${unit_dir}/${service}"
    grep -qFx 'PrivateTmp=true' "${unit_dir}/${service}"
done
for timer in proton-drive-update.timer rclone-selfupdate.timer; do
    grep -qFx 'Persistent=true' "${unit_dir}/${timer}"
    grep -qFx 'FixedRandomDelay=true' "${unit_dir}/${timer}"
    grep -qE '^RandomizedDelaySec=.+$' "${unit_dir}/${timer}"
done
if grep -qFx '[Install]' "${unit_dir}/proton-drive-update.service"; then
    printf 'The optional Proton CLI updater service must be timer-triggered only.\n' >&2
    exit 1
fi

if command -v systemd-analyze >/dev/null 2>&1; then
    verify_output=''
    set +e
    verify_output="$(systemd-analyze --user verify \
        "${unit_dir}"/*.service "${unit_dir}"/*.timer 2>&1)"
    verify_status=$?
    set -e
    verify_output="$(grep -Ev \
        -e '^Failed to (bind private socket|connect to system bus): Operation not permitted$' \
        -e '^(pdrive-draft-recovery|pdrive-watch|proton-drive-update|rclone-proton-drive|rclone-selfupdate)\.service: Command /[^ ]+/\.local/(bin|libexec)/(pdrive-auth-failure-guard|pdrive-bwlimit|pdrive-draft-recovery-auto|pdrive-watch|proton-drive-update|rclone-proton-mount|rclone-selfupdate)( --apply-startup| --auto| --after-service-exit| --begin-start| --mark-healthy| --start-allowed)? is not executable: No such file or directory$' \
        <<< "${verify_output}" || true)"
    if (( verify_status != 0 )) && [[ -n "${verify_output}" ]]; then
        printf '%s\n' "${verify_output}" >&2
        exit "${verify_status}"
    fi
    if [[ -n "${verify_output}" ]]; then
        printf '%s\n' "${verify_output}" >&2
    fi
fi

printf 'PDrive systemd user-unit checks passed.\n'
