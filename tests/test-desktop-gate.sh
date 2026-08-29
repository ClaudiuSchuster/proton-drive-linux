#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-desktop-gate.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

test_home="${test_root}/home"
mkdir -p -- "${test_home}"
cat > "${test_root}/os-release" <<'EOF'
ID=arch
VERSION_ID=rolling
PRETTY_NAME="Arch Linux"
EOF

snapshot() {
    find "${test_home}" -mindepth 1 -printf '%P|%y|%s\n' | sort
}

before="$(snapshot)"
HOME="${test_home}" PDRIVE_OS_RELEASE="${test_root}/os-release" \
    PATH='/usr/bin:/bin' "${project_dir}/bin/pdrive-desktop-gate" --help >/dev/null
HOME="${test_home}" PDRIVE_OS_RELEASE="${test_root}/os-release" \
    PATH='/usr/bin:/bin' "${project_dir}/bin/pdrive-desktop-gate" >/dev/null
after="$(snapshot)"
if [[ "${before}" != "${after}" ]]; then
    printf 'Desktop-gate help changed the test HOME.\n' >&2
    exit 1
fi

common_environment=(
    HOME="${test_home}"
    PDRIVE_OS_RELEASE="${test_root}/os-release"
    PATH='/usr/bin:/bin'
    XDG_CURRENT_DESKTOP='FixtureDesktop'
    XDG_SESSION_TYPE='tty'
)
json_report="$(
    env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
        "${common_environment[@]}" \
        "${project_dir}/bin/pdrive-desktop-gate" --json
)"
python3 - "${json_report}" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert report["schema_version"] == 1
assert report["mode"] == "preflight"
assert report["platform"] == {
    "id": "arch",
    "version_id": "rolling",
    "family": "arch",
    "architecture": report["platform"]["architecture"],
    "desktop": "FixtureDesktop",
    "session_type": "tty",
}
assert report["summary"]["automated_ready"] is False
assert report["summary"]["fail"] > 0
assert {item["status"] for item in report["results"]} <= {"PASS", "FAIL", "SKIP"}
result_ids = {item["id"] for item in report["results"]}
assert {
    "distribution-adapter",
    "packages",
    "graphical-session",
    "session-bus",
    "systemd-user",
    "gtk",
    "tray-library",
    "fuse-device",
    "installed-helpers",
    "desktop-entry",
    "desktop-icon",
    "systemd-units",
    "mountpoint",
    "control-center-check",
} <= result_ids
assert {item["id"] for item in report["manual_gates"]} >= {
    "menu-launch",
    "window-layout",
    "language-and-keyboard",
    "tray-behavior",
    "file-manager",
    "login-lifecycle",
    "configured-transfer",
}
assert "hostname" in report["privacy"].lower()
PY

if env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    "${common_environment[@]}" \
    "${project_dir}/bin/pdrive-desktop-gate" --json --strict >/dev/null; then
    printf 'Strict desktop gate accepted an intentionally incomplete fixture.\n' >&2
    exit 1
fi

configured_report="$(
    env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
        "${common_environment[@]}" \
        "${project_dir}/bin/pdrive-desktop-gate" --configured --json
)"
python3 - "${configured_report}" <<'PY'
import json
import sys

report = json.loads(sys.argv[1])
assert report["mode"] == "configured"
result_ids = {item["id"] for item in report["results"]}
assert {
    "encrypted-config",
    "mount-service",
    "fuse-mount",
    "state-snapshot",
    "keyring-entry",
} <= result_ids
PY

markdown_report="$(
    env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
        "${common_environment[@]}" \
        "${project_dir}/bin/pdrive-desktop-gate" --markdown
)"
grep -qF '# PDrive desktop gate report' <<< "${markdown_report}"
grep -qF "Automated gate: \`FAIL\`" <<< "${markdown_report}"
grep -qF 'Manual confirmation still required' <<< "${markdown_report}"
if grep -Fq -- "${test_home}" <<< "${json_report}${configured_report}${markdown_report}"; then
    printf 'Desktop-gate report leaked the test HOME.\n' >&2
    exit 1
fi

printf 'PDrive desktop-gate report checks passed.\n'
