#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
runtime="${PDRIVE_CONTAINER_RUNTIME:-podman}"
pull_policy='never'

usage() {
    printf '%s\n' \
        'Usage: tests/run-arch-package.sh [--runtime podman|docker] [--pull]' \
        '' \
        'Builds, inspects and installs one native Arch package in a disposable container.' \
        'The source checkout is read-only; completed packages are written under dist/.'
}

while (( $# )); do
    case "${1}" in
        --runtime)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            runtime="${2}"
            shift 2
            ;;
        --pull)
            pull_policy='always'
            shift
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
case "${runtime}" in
    podman|docker) ;;
    *) printf 'Unsupported container runtime: %s\n' "${runtime}" >&2; exit 2 ;;
esac
command -v "${runtime}" >/dev/null 2>&1 || {
    printf 'Container runtime is unavailable: %s\n' "${runtime}" >&2
    exit 69
}

image='docker.io/library/archlinux:base'
if [[ "${runtime}" == podman ]]; then
    image_present() { podman image exists "${1}"; }
else
    image_present() { docker image inspect "${1}" >/dev/null 2>&1; }
fi
if [[ "${pull_policy}" == never ]] && ! image_present "${image}"; then
    printf 'Image is not present locally: %s\nRun again with --pull to download it explicitly.\n' \
        "${image}" >&2
    exit 69
fi

version="$(< "${project_dir}/VERSION")"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    printf 'Invalid project version: %s\n' "${version}" >&2
    exit 1
}
source_epoch="$(git -C "${project_dir}" log -1 --format=%ct)"
input_dir="$(mktemp -d /tmp/proton-drive-linux-arch-input.XXXXXX)"
cleanup() { rm -rf -- "${input_dir}"; }
trap cleanup EXIT
output_dir="${project_dir}/dist/arch"
mkdir -p -- "${output_dir}"
archive_name="proton-drive-linux-${version}.tar.gz"
archive_path="${input_dir}/${archive_name}"

git -C "${project_dir}" ls-files --cached --others --exclude-standard -z \
    | LC_ALL=C sort -z \
    | tar -C "${project_dir}" --null --files-from=- \
        --sort=name --mtime="@${source_epoch}" --owner=0 --group=0 --numeric-owner \
        --transform="s,^,proton-drive-linux-${version}/," \
        -czf "${archive_path}"
source_sha256="$(sha256sum "${archive_path}" | awk '{ print $1 }')"
"${project_dir}/packaging/arch/render-pkgbuild" \
    --source-url "file:///input/${archive_name}" \
    --source-sha256 "${source_sha256}" \
    --output "${input_dir}/PKGBUILD"

# The variables inside this command are intentionally expanded by the container shell.
# shellcheck disable=SC2016
container_script='set -euxo pipefail
pacman -Syu --needed --noconfirm fakeroot namcap
useradd --create-home builder
install -d -m 0755 -o builder -g builder /build
cp /input/PKGBUILD /input/proton-drive-linux-*.tar.gz /build/
chown -R builder:builder /build
su builder -c "cd /build && SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH} makepkg --cleanbuild --nodeps --noconfirm"
package_path="$(find /build -maxdepth 1 -type f -name "proton-drive-linux-*.pkg.tar.zst" -print -quit)"
test -n "${package_path}"
cp "${package_path}" /output/
namcap /build/PKGBUILD "${package_path}" | tee /tmp/namcap.txt
if grep -q " E: " /tmp/namcap.txt; then
    printf "namcap reported a package error.\n" >&2
    exit 1
fi
bsdtar -tf "${package_path}" > /tmp/package-files.txt
grep -qFx usr/share/doc/proton-drive-linux/OPERATIONS.md /tmp/package-files.txt
grep -qFx usr/share/doc/proton-drive-linux/docs/assets/pdrive-control-center.png /tmp/package-files.txt
grep -qFx usr/share/licenses/proton-drive-linux/LICENSE /tmp/package-files.txt
pacman -Udd --noconfirm "${package_path}"
test "$(readlink /usr/bin/pdrive-ui)" = "../lib/proton-drive-linux/bin/pdrive-ui"
test -x /usr/lib/proton-drive-linux/libexec/rclone-proton-mount
test -r /usr/lib/systemd/user/rclone-proton-drive.service
test -r /usr/share/licenses/proton-drive-linux/LICENSE
if pacman -Ql proton-drive-linux | grep -q "proton-drive-linux /home/"; then
    printf "The native package owns a home-directory path.\n" >&2
    exit 1
fi
HOME=/tmp/pdrive-empty-home pdrive-service --help >/dev/null
HOME=/tmp/pdrive-empty-home pdrive-platform --family | grep -qx arch
grep -qFx "ExecStart=/usr/bin/env pdrive-service mount" /usr/lib/systemd/user/rclone-proton-drive.service
'

printf 'Building Arch package %s from checksum %s.\n' "${version}" "${source_sha256}"
"${runtime}" run --rm --pull="${pull_policy}" \
    --env "SOURCE_DATE_EPOCH=${source_epoch}" \
    --mount "type=bind,source=${input_dir},target=/input,readonly" \
    --mount "type=bind,source=${output_dir},target=/output" \
    "${image}" bash -lc "${container_script}"

package_path="$(find "${output_dir}" -maxdepth 1 -type f \
    -name "proton-drive-linux-${version}-1-any.pkg.tar.zst" -print -quit)"
[[ -n "${package_path}" ]] || {
    printf 'The expected Arch package was not produced.\n' >&2
    exit 1
}
printf 'Arch package gate passed: %s\n' "${package_path}"
