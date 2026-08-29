#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
test_root="$(mktemp -d /tmp/proton-drive-linux-install-layout.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

user_root="${test_root}/user"
system_root="${test_root}/system"
mkdir -p -- "${user_root}" "${system_root}"

"${project_dir}/packaging/install-static.sh" --layout user --destdir "${user_root}"
"${project_dir}/packaging/install-static.sh" --layout system --destdir "${system_root}"

for command_name in pdrive-service pdrive-ui rclone; do
    [[ -x "${user_root}/.local/bin/${command_name}" ]]
    [[ -x "${system_root}/usr/lib/proton-drive-linux/bin/${command_name}" ]]
    [[ -L "${system_root}/usr/bin/${command_name}" ]]
    [[ "$(readlink -- "${system_root}/usr/bin/${command_name}")" \
        == "../lib/proton-drive-linux/bin/${command_name}" ]]
done
for helper_name in pdrive-account-cache rclone-proton-mount setup-rclone-proton; do
    [[ -x "${user_root}/.local/libexec/${helper_name}" ]]
    [[ -x "${system_root}/usr/lib/proton-drive-linux/libexec/${helper_name}" ]]
done
for unit_name in rclone-proton-drive.service pdrive-watch.timer; do
    [[ -r "${user_root}/.config/systemd/user/${unit_name}" ]]
    [[ -r "${system_root}/usr/lib/systemd/user/${unit_name}" ]]
done
for relative_path in \
    usr/share/applications/io.github.claudiuschuster.PDriveControl.desktop \
    usr/share/doc/proton-drive-linux/OPERATIONS.md \
    usr/share/doc/proton-drive-linux/docs/assets/pdrive-control-center.png \
    usr/share/icons/hicolor/scalable/apps/io.github.claudiuschuster.PDriveControl.svg \
    usr/share/licenses/proton-drive-linux/LICENSE; do
    [[ -s "${system_root}/${relative_path}" ]]
done
for source_path in "${project_dir}"/docs/*.md; do
    cmp --silent -- "${source_path}" \
        "${system_root}/usr/share/doc/proton-drive-linux/$(basename -- "${source_path}")"
done
for source_path in "${project_dir}"/docs/assets/*; do
    cmp --silent -- "${source_path}" \
        "${system_root}/usr/share/doc/proton-drive-linux/docs/assets/$(basename -- "${source_path}")"
done

if find "${system_root}" -path '*/home/*' -print -quit | grep -q .; then
    printf 'The system package layout unexpectedly contains a home directory.\n' >&2
    exit 1
fi
if find "${system_root}" -type f -print0 \
    | xargs -0 grep -IlF -- "${user_root}" | grep -q .; then
    printf 'The staged package contains its temporary user path.\n' >&2
    exit 1
fi

HOME="${test_root}/empty-home" \
    "${system_root}/usr/lib/proton-drive-linux/bin/pdrive-service" --help >/dev/null
if HOME="${test_root}/empty-home" \
    "${system_root}/usr/lib/proton-drive-linux/bin/pdrive-service" arbitrary-command \
    >/dev/null 2>&1; then
    printf 'The service dispatcher accepted an arbitrary command.\n' >&2
    exit 1
fi

rendered_pkgbuild="${test_root}/PKGBUILD"
"${project_dir}/packaging/arch/render-pkgbuild" \
    --source-sha256 "$(printf 'a%.0s' {1..64})" \
    --output "${rendered_pkgbuild}"
bash -n "${rendered_pkgbuild}"
grep -qF 'pkgname=proton-drive-linux' "${rendered_pkgbuild}"
grep -qF "pkgver=$(< "${project_dir}/VERSION")" "${rendered_pkgbuild}"
if grep -Eq '@(VERSION|SOURCE_URL|SOURCE_SHA256)@' "${rendered_pkgbuild}"; then
    printf 'The rendered PKGBUILD still contains a template token.\n' >&2
    exit 1
fi

printf 'Relocatable user and system installation layouts passed.\n'
