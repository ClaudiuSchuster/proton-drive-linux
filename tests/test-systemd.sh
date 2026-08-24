#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
unit_dir="${project_dir}/systemd/user"
expected_units=(
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

for service in pdrive-watch.service proton-drive-update.service \
    rclone-proton-drive.service rclone-selfupdate.service; do
    grep -qFx 'UMask=0077' "${unit_dir}/${service}"
done

mount_unit="${unit_dir}/rclone-proton-drive.service"
grep -qFx 'Type=notify' "${mount_unit}"
grep -qFx 'TimeoutStartSec=infinity' "${mount_unit}"
grep -qFx 'RestartSec=1h' "${mount_unit}"
if grep -Eq '^(NoNewPrivileges|PrivateDevices|PrivateMounts|ProtectHome)=' "${mount_unit}"; then
    printf 'The FUSE/Keyring mount unit gained incompatible generic sandboxing.\n' >&2
    exit 1
fi

for service in pdrive-watch.service proton-drive-update.service rclone-selfupdate.service; do
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
    if ! verify_output="$(systemd-analyze --user verify \
        "${unit_dir}"/*.service "${unit_dir}"/*.timer 2>&1)"; then
        printf '%s\n' "${verify_output}" >&2
        exit 1
    fi
    verify_output="$(grep -Ev \
        '^Failed to (bind private socket|connect to system bus): Operation not permitted$' \
        <<< "${verify_output}" || true)"
    if [[ -n "${verify_output}" ]]; then
        printf '%s\n' "${verify_output}" >&2
    fi
fi

printf 'PDrive systemd user-unit checks passed.\n'
