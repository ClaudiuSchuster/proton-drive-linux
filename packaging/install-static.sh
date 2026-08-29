#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
umask 022

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
layout=''
destination=''
prefix='/usr'

usage() {
    printf '%s\n' \
        'Usage: packaging/install-static.sh --layout user|system --destdir DIRECTORY [--prefix /usr]' \
        '' \
        'Stages only immutable PDrive application files.' \
        'It never creates /pdrive, writes user configuration, enables units or starts services.'
}

while (( $# )); do
    case "${1}" in
        --layout)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            layout="${2}"
            shift 2
            ;;
        --destdir)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            destination="${2}"
            shift 2
            ;;
        --prefix)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            prefix="${2}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

case "${layout}" in
    user|system) ;;
    *) usage >&2; exit 2 ;;
esac
[[ -n "${destination}" && "${destination}" == /* ]] || {
    printf 'The destination must be an absolute directory.\n' >&2
    exit 2
}
[[ "${prefix}" == /* && "${prefix}" != */ ]] || {
    printf 'The prefix must be an absolute path without a trailing slash.\n' >&2
    exit 2
}

install_tree() {
    local source_dir="${1}" target_dir="${2}" mode="${3}" source_file
    for source_file in "${source_dir}"/*; do
        [[ -f "${source_file}" ]] || continue
        install -Dm "${mode}" -- "${source_file}" \
            "${target_dir}/$(basename -- "${source_file}")"
    done
}

if [[ "${layout}" == user ]]; then
    app_root="${destination}/.local"
    bin_dir="${app_root}/bin"
    libexec_dir="${app_root}/libexec"
    unit_dir="${destination}/.config/systemd/user"
    data_root="${app_root}/share"
else
    app_root="${destination}${prefix}/lib/proton-drive-linux"
    bin_dir="${app_root}/bin"
    libexec_dir="${app_root}/libexec"
    unit_dir="${destination}${prefix}/lib/systemd/user"
    data_root="${destination}${prefix}/share"
fi
doc_dir="${data_root}/doc/proton-drive-linux"

install_tree "${project_dir}/bin" "${bin_dir}" 0755
install_tree "${project_dir}/libexec" "${libexec_dir}" 0755
install_tree "${project_dir}/systemd/user" "${unit_dir}" 0644
install -Dm 0644 -- "${project_dir}/README.md" "${doc_dir}/README.md"
install_tree "${project_dir}/docs" "${doc_dir}" 0644
install_tree "${project_dir}/docs/assets" "${doc_dir}/docs/assets" 0644
install -Dm 0644 -- "${project_dir}/SECURITY.md" "${doc_dir}/SECURITY.md"
install -Dm 0644 -- "${project_dir}/LICENSE" "${doc_dir}/LICENSE"
install -Dm 0644 -- "${project_dir}/VERSION" "${doc_dir}/VERSION"
install -Dm 0644 -- \
    "${project_dir}/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg" \
    "${doc_dir}/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg"
install -Dm 0644 -- \
    "${project_dir}/share/applications/io.github.claudiuschuster.PDriveControl.desktop" \
    "${data_root}/applications/io.github.claudiuschuster.PDriveControl.desktop"
install -Dm 0644 -- \
    "${project_dir}/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg" \
    "${data_root}/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg"

if [[ "${layout}" == system ]]; then
    system_bin_dir="${destination}${prefix}/bin"
    mkdir -p -- "${system_bin_dir}"
    for source_file in "${project_dir}"/bin/*; do
        [[ -f "${source_file}" ]] || continue
        command_name="$(basename -- "${source_file}")"
        ln -sfn -- "../lib/proton-drive-linux/bin/${command_name}" \
            "${system_bin_dir}/${command_name}"
    done
    install -Dm 0644 -- "${project_dir}/LICENSE" \
        "${data_root}/licenses/proton-drive-linux/LICENSE"
fi
