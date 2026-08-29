#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runtime="${PDRIVE_CONTAINER_RUNTIME:-}"
pull_policy='never'
target=''

usage() {
    printf '%s\n' \
        'Usage: tests/run-distro-smoke.sh [--runtime podman|docker] [--pull] arch|ubuntu|all' \
        '' \
        'Runs disposable compatibility checks with the repository mounted read-only.' \
        'Images are never downloaded unless --pull is explicit.'
}

while (( $# )); do
    case "$1" in
        --runtime)
            (( $# >= 2 )) || { usage >&2; exit 2; }
            runtime="$2"
            shift 2
            ;;
        --pull)
            pull_policy='always'
            shift
            ;;
        arch|ubuntu|all)
            [[ -z "${target}" ]] || { usage >&2; exit 2; }
            target="$1"
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
[[ -n "${target}" ]] || { usage >&2; exit 2; }

if [[ -z "${runtime}" ]]; then
    if command -v podman >/dev/null 2>&1; then
        runtime='podman'
    elif command -v docker >/dev/null 2>&1; then
        runtime='docker'
    else
        printf 'Neither podman nor docker is available.\n' >&2
        exit 69
    fi
fi
case "${runtime}" in
    podman|docker) ;;
    *) printf 'Unsupported container runtime: %s\n' "${runtime}" >&2; exit 2 ;;
esac

run_target() {
    local distro="$1" image setup_command image_id
    case "${distro}" in
        arch)
            image='docker.io/library/archlinux:base'
            setup_command='pacman -Syu --needed --noconfirm bash coreutils curl desktop-file-utils fuse3 gnome-keyring gtk3 iproute2 jq libayatana-appindicator libnotify libsecret openssl polkit python python-cairo python-gobject shared-mime-info systemd util-linux xorg-server-xvfb && /workspace/tests/test-distro-smoke.sh arch'
            ;;
        ubuntu)
            image='docker.io/library/ubuntu:24.04'
            setup_command='export DEBIAN_FRONTEND=noninteractive; apt-get update && apt-get install -y bash coreutils curl desktop-file-utils fuse3 gir1.2-ayatanaappindicator3-0.1 gir1.2-gtk-3.0 gnome-keyring iproute2 jq libfuse3-3 libnotify-bin libpam-gnome-keyring libsecret-tools openssl policykit-1 python3 python3-cairo python3-gi python3-gi-cairo shared-mime-info util-linux xvfb && /workspace/tests/test-distro-smoke.sh debian'
            ;;
        *) return 2 ;;
    esac

    if [[ "${runtime}" == podman ]]; then
        image_present() { podman image exists "$1"; }
    else
        image_present() { docker image inspect "$1" >/dev/null 2>&1; }
    fi
    if [[ "${pull_policy}" == never ]] && ! image_present "${image}"; then
        printf 'Image is not present locally: %s\nRun again with --pull to download it explicitly.\n' \
            "${image}" >&2
        return 69
    fi

    printf 'Running %s smoke checks in %s with %s (pull=%s).\n' \
        "${distro}" "${image}" "${runtime}" "${pull_policy}"
    "${runtime}" run --rm --pull="${pull_policy}" \
        --mount "type=bind,source=${project_dir},target=/workspace,readonly" \
        --workdir /workspace \
        "${image}" bash -lc "${setup_command}"
    image_id="$("${runtime}" image inspect --format '{{.Id}}' "${image}")"
    printf 'Verified image: %s (%s); no container or volume was retained.\n' \
        "${image}" "${image_id}"
}

case "${target}" in
    arch) run_target arch ;;
    ubuntu) run_target ubuntu ;;
    all)
        run_target ubuntu
        run_target arch
        ;;
esac
