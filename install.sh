#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
umask 022

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bin_dir="${HOME}/.local/bin"
libexec_dir="${HOME}/.local/libexec"
unit_dir="${HOME}/.config/systemd/user"
doc_dir="${HOME}/.local/share/doc/proton-drive-linux"
doc_assets_dir="${doc_dir}/docs/assets"
doc_icon_dir="${doc_dir}/share/icons/hicolor/scalable/apps"
applications_dir="${HOME}/.local/share/applications"
icons_dir="${HOME}/.local/share/icons/hicolor/scalable/apps"
config_dir="${HOME}/.config"
real_rclone="${libexec_dir}/rclone-bin"
mount_dir='/pdrive'
enable_proton_cli_updater=false

usage() {
    printf '%s\n' \
        'Usage: ./install.sh [--with-proton-cli-updater]' \
        '' \
        'Installs or updates the user-local helpers, systemd units and docs.' \
        'On a fresh install, bootstraps the latest signed stable rclone from an' \
        'already installed rclone binary. Existing personal configuration,' \
        'cache, logs and a running mount are never overwritten or restarted.' \
        '' \
        '--with-proton-cli-updater  also enable the optional official Proton' \
        '                           Drive CLI update timer.' \
        '-h, --help                 only show this help.'
}

case "${1:-}" in
    '')
        (( $# == 0 )) || { usage >&2; exit 2; }
        ;;
    --with-proton-cli-updater)
        (( $# == 1 )) || { usage >&2; exit 2; }
        enable_proton_cli_updater=true
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

missing_commands=()
for command_name in bash curl findmnt flock fusermount3 jq mountpoint openssl \
    python3 secret-tool ss sudo systemctl timeout; do
    command -v "${command_name}" >/dev/null 2>&1 || missing_commands+=("${command_name}")
done
if (( ${#missing_commands[@]} != 0 )); then
    printf 'Missing required commands: %s\n' "${missing_commands[*]}" >&2
    printf 'Install the packages listed in README.md, then run this installer again.\n' >&2
    exit 69
fi
if ! python3 -c \
    "import gi; import cairo; gi.require_foreign('cairo'); gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" \
    >/dev/null 2>&1; then
    printf '%s\n' \
        'Missing GTK/Cairo Python bindings for PDrive Control Center.' \
        'On Debian/Ubuntu install: python3-gi python3-gi-cairo gir1.2-gtk-3.0' >&2
    exit 69
fi
if ! python3 -c \
    "import gi; gi.require_version('AyatanaAppIndicator3', '0.1'); from gi.repository import AyatanaAppIndicator3" \
    >/dev/null 2>&1; then
    printf '%s\n' \
        'Missing Ayatana AppIndicator binding for the Cinnamon tray.' \
        'On Debian/Ubuntu install: gir1.2-ayatanaappindicator3-0.1' >&2
    exit 69
fi

bootstrap_rclone=''
if [[ -x "${real_rclone}" ]]; then
    bootstrap_rclone="${real_rclone}"
elif command -v rclone >/dev/null 2>&1; then
    bootstrap_rclone="$(command -v rclone)"
fi
if [[ -z "${bootstrap_rclone}" || ! -x "${bootstrap_rclone}" ]]; then
    printf 'No bootstrap rclone found. Install the distribution rclone package first.\n' >&2
    exit 69
fi

if [[ -L "${mount_dir}" ]]; then
    printf 'Refusing symlink mountpoint: %s\n' "${mount_dir}" >&2
    exit 73
fi
if mountpoint -q -- "${mount_dir}"; then
    mounted_fstype="$(findmnt -rn -M "${mount_dir}" -o FSTYPE 2>/dev/null || true)"
    case "${mounted_fstype}" in
        fuse.rclone|fuse) ;;
        *)
            printf 'Refusing unexpected filesystem at %s (%s).\n' \
                "${mount_dir}" "${mounted_fstype:-unknown}" >&2
            exit 73
            ;;
    esac
else
    sudo install -d -m 0700 -o "$(id -un)" -g "$(id -gn)" "${mount_dir}"
fi
if [[ ! -d "${mount_dir}" \
    || "$(stat -c %u -- "${mount_dir}" 2>/dev/null || true)" != "$(id -u)" ]]; then
    printf 'Mountpoint is not a real directory owned by this user: %s\n' "${mount_dir}" >&2
    exit 73
fi

mkdir -p -- "${bin_dir}" "${libexec_dir}" "${unit_dir}" "${doc_dir}" \
    "${doc_assets_dir}" "${doc_icon_dir}" \
    "${applications_dir}" "${icons_dir}" "${config_dir}"

if [[ ! -x "${real_rclone}" ]]; then
    temporary_rclone="$(mktemp "${libexec_dir}/.rclone-bin.XXXXXX")"
    cleanup_rclone() { rm -f -- "${temporary_rclone:-}"; }
    trap cleanup_rclone EXIT
    install -m 0755 "${bootstrap_rclone}" "${temporary_rclone}"
    "${temporary_rclone}" selfupdate --stable
    if ! "${temporary_rclone}" help backend protondrive >/dev/null 2>&1; then
        printf 'The downloaded rclone does not provide the protondrive backend.\n' >&2
        exit 70
    fi
    mv -f -- "${temporary_rclone}" "${real_rclone}"
    trap - EXIT
fi

for source_file in "${project_dir}"/bin/*; do
    [[ -f "${source_file}" ]] || continue
    install -m 0755 "${source_file}" "${bin_dir}/$(basename -- "${source_file}")"
done
for source_file in "${project_dir}"/libexec/*; do
    [[ -f "${source_file}" ]] || continue
    install -m 0755 "${source_file}" "${libexec_dir}/$(basename -- "${source_file}")"
done
for source_file in "${project_dir}"/systemd/user/*; do
    install -m 0644 "${source_file}" "${unit_dir}/$(basename -- "${source_file}")"
done
install -m 0644 "${project_dir}/README.md" "${doc_dir}/README.md"
install -m 0644 "${project_dir}/docs/OPERATIONS.md" "${doc_dir}/OPERATIONS.md"
install -m 0644 "${project_dir}/docs/TROUBLESHOOTING.md" "${doc_dir}/TROUBLESHOOTING.md"
install -m 0644 "${project_dir}/docs/DEVELOPMENT.md" "${doc_dir}/DEVELOPMENT.md"
install -m 0644 "${project_dir}/SECURITY.md" "${doc_dir}/SECURITY.md"
install -m 0644 "${project_dir}/LICENSE" "${doc_dir}/LICENSE"
install -m 0644 "${project_dir}/VERSION" "${doc_dir}/VERSION"
install -m 0644 \
    "${project_dir}/docs/assets/pdrive-control-center.png" \
    "${doc_assets_dir}/pdrive-control-center.png"
install -m 0644 \
    "${project_dir}/docs/assets/pdrive-control-menu.png" \
    "${doc_assets_dir}/pdrive-control-menu.png"
install -m 0644 \
    "${project_dir}/docs/assets/pdrive-transfers.png" \
    "${doc_assets_dir}/pdrive-transfers.png"
install -m 0644 \
    "${project_dir}/docs/assets/pdrive-history.png" \
    "${doc_assets_dir}/pdrive-history.png"
install -m 0644 \
    "${project_dir}/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg" \
    "${doc_icon_dir}/io.github.claudiuschuster.PDriveControl.svg"
install -m 0644 \
    "${project_dir}/share/applications/io.github.claudiuschuster.PDriveControl.desktop" \
    "${applications_dir}/io.github.claudiuschuster.PDriveControl.desktop"
install -m 0644 \
    "${project_dir}/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg" \
    "${icons_dir}/io.github.claudiuschuster.PDriveControl.svg"
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${applications_dir}" >/dev/null 2>&1 || true
fi

create_default() {
    local path="$1"
    local line="$2"
    if [[ ! -e "${path}" ]]; then
        printf '%s\n' '# Managed by proton-drive-linux; do not source as shell code.' "${line}" > "${path}"
        chmod 0600 "${path}"
    fi
}
create_default "${config_dir}/pdrive-bwlimit.conf" 'bwlimit=off'
create_default "${config_dir}/pdrive-cache.conf" 'cache_max_age_hours=24'
create_default "${config_dir}/pdrive-recovery.conf" 'proton_metadata_cache=false'
create_default "${config_dir}/pdrive-draft-recovery.conf" 'replace_existing_draft=false'
create_default "${config_dir}/pdrive-transfers.conf" 'transfers=4'

systemctl --user daemon-reload
systemctl --user enable rclone-selfupdate.timer >/dev/null
if [[ -r "${HOME}/.config/rclone/rclone.conf" ]]; then
    systemctl --user enable --now rclone-proton-drive.service pdrive-watch.timer \
        pdrive-draft-recovery.timer >/dev/null
fi
if [[ "${enable_proton_cli_updater}" == true ]]; then
    systemctl --user enable proton-drive-update.timer >/dev/null
fi

printf '%s\n' \
    'proton-drive-linux installed.' \
    'No running rclone process or transfer was restarted.' \
    'Open “PDrive Control Center” from the desktop menu or run pdrive-ui.'
if [[ ! -e "${HOME}/.config/rclone/rclone.conf" ]]; then
    printf '%s\n' 'Next: open PDrive Control Center for guided setup, or run pdrive-setup --setup.'
else
    printf '%s\n' 'Existing encrypted configuration retained. Check with pdrive-doctor.'
fi
case ":${PATH}:" in
    *:"${bin_dir}":*) ;;
    *) printf 'Note: add %s to PATH to invoke the helpers by name.\n' "${bin_dir}" ;;
esac
