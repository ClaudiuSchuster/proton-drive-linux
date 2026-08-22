#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

bin_dir="${HOME}/.local/bin"
libexec_dir="${HOME}/.local/libexec"
unit_dir="${HOME}/.config/systemd/user"
doc_dir="${HOME}/.local/share/doc/proton-drive-linux"
state_dir="${HOME}/.local/state/rclone"
rc_socket="${state_dir}/pdrive-rc.sock"
rclone_bin="${libexec_dir}/rclone-bin"

usage() {
    printf '%s\n' \
        'Usage: ./uninstall.sh [--uninstall]' \
        '' \
        'Without --uninstall or with --help, this command is action-free.' \
        '--uninstall refuses to continue while the VFS queue or any local' \
        'Proton Dirty file is present, then disables the managed services and' \
        'removes only files installed by this repository.' \
        '' \
        'Personal rclone configuration, GNOME-Keyring secret, cache, logs and' \
        'the empty /pdrive directory are deliberately retained.'
}

case "${1:-}" in
    '')
        (( $# == 0 )) || { usage >&2; exit 2; }
        usage
        exit 0
        ;;
    --uninstall)
        (( $# == 1 )) || { usage >&2; exit 2; }
        ;;
    -h|--help)
        (( $# == 1 )) || { usage >&2; exit 2; }
        usage
        exit 0
        ;;
    *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

queue_count=0
if [[ -S "${rc_socket}" && -x "${rclone_bin}" ]] && command -v jq >/dev/null 2>&1; then
    if ! queue_json="$(timeout --signal=TERM 10s "${rclone_bin}" rc \
        --unix-socket "${rc_socket}" vfs/queue 2>/dev/null)" \
        || ! jq -e '.queue | type == "array"' >/dev/null 2>&1 <<< "${queue_json}"; then
        printf 'Cannot safely inspect the live VFS queue; uninstall refused.\n' >&2
        exit 75
    fi
    queue_count="$(jq -r '.queue | length' <<< "${queue_json}")"
fi

dirty_count=0
if [[ -d "${HOME}/.cache/rclone/vfsMeta" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
        printf 'Cannot safely inspect VFS metadata without jq; uninstall refused.\n' >&2
        exit 75
    fi
    dirty_count="$(find "${HOME}/.cache/rclone/vfsMeta" -mindepth 2 -type f \
        -path '*/proton*/*' -print0 2>/dev/null \
        | xargs -0 -r jq -r 'select(.Dirty == true) | 1' 2>/dev/null \
        | awk '{ count += $1 } END { print count + 0 }')"
fi
if (( queue_count != 0 || dirty_count != 0 )); then
    printf 'Uninstall refused: VFS queue %s, Dirty files %s.\n' \
        "${queue_count}" "${dirty_count}" >&2
    printf 'Let uploads finish and check pdrive-watch before trying again.\n' >&2
    exit 75
fi

if [[ ! -t 0 ]]; then
    printf 'Run --uninstall in an interactive terminal.\n' >&2
    exit 64
fi
printf '%s\n' \
    'This stops the Proton Drive mount and removes the installed toolkit.' \
    'Configuration, keyring entry, cache and logs will be retained.'
printf 'Type UNINSTALL to continue: '
IFS= read -r confirmation
if [[ "${confirmation}" != 'UNINSTALL' ]]; then
    printf 'Cancelled; nothing was changed.\n'
    exit 0
fi

systemctl --user disable --now \
    pdrive-watch.timer rclone-proton-drive.service \
    rclone-selfupdate.timer proton-drive-update.timer >/dev/null 2>&1 || true

for file_name in pdrive-bwlimit pdrive-doctor pdrive-draft-recovery pdrive-reauth \
    pdrive-recovery pdrive-refresh pdrive-setup pdrive-transfers pdrive-watch rclone; do
    rm -f -- "${bin_dir}/${file_name}"
done
for file_name in proton-drive-update rclone-bin rclone-proton-mount \
    rclone-proton-unmount rclone-selfupdate setup-rclone-proton; do
    rm -f -- "${libexec_dir}/${file_name}"
done
for file_name in pdrive-watch.service pdrive-watch.timer \
    proton-drive-update.service proton-drive-update.timer \
    rclone-proton-drive.service rclone-selfupdate.service rclone-selfupdate.timer; do
    rm -f -- "${unit_dir}/${file_name}"
done
if [[ -d "${doc_dir}" ]]; then
    find "${doc_dir}" -mindepth 1 -maxdepth 1 -type f \
        \( -name README.md -o -name OPERATIONS.md -o -name TROUBLESHOOTING.md -o -name LICENSE \) \
        -delete
    rmdir "${doc_dir}" 2>/dev/null || true
fi
systemctl --user daemon-reload

printf '%s\n' \
    'proton-drive-linux removed.' \
    'Retained: ~/.config/rclone, ~/.config/pdrive-*.conf, ~/.cache/rclone,' \
    "${HOME}/.local/state/rclone, the GNOME-Keyring secret and /pdrive."
