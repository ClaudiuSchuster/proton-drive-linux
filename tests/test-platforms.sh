#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-platforms.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

platform_info() {
    PDRIVE_OS_RELEASE="$1" PYTHONDONTWRITEBYTECODE=1 \
        python3 "${project_dir}/bin/pdrive-platform" --json
}

cat > "${test_root}/ubuntu" <<'EOF'
NAME="Ubuntu"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 24.04 LTS"
EOF
ubuntu_json="$(platform_info "${test_root}/ubuntu")"
jq -e '
    .id == "ubuntu"
    and .family == "debian"
    and .package_manager == "/usr/bin/apt-get"
    and .install_arguments == ["install", "-y"]
    and (.packages | index("python3-gi")) != null
    and (.packages | index("gir1.2-ayatanaappindicator3-0.1")) != null
' >/dev/null <<< "${ubuntu_json}"

cat > "${test_root}/mint" <<'EOF'
NAME="Linux Mint"
ID=linuxmint
ID_LIKE="ubuntu debian"
PRETTY_NAME="Linux Mint 22.3"
EOF
mint_json="$(platform_info "${test_root}/mint")"
jq -e '.family == "debian" and .id_like == ["ubuntu", "debian"]' \
    >/dev/null <<< "${mint_json}"

cat > "${test_root}/arch" <<'EOF'
NAME="Arch Linux"
ID=arch
PRETTY_NAME="Arch Linux"
EOF
arch_json="$(platform_info "${test_root}/arch")"
jq -e '
    .id == "arch"
    and .family == "arch"
    and .package_manager == "/usr/bin/pacman"
    and .install_arguments == ["-S", "--needed", "--noconfirm"]
    and .manual_command == ["sudo", "pacman", "-S", "--needed"]
    and (.packages | index("python-gobject")) != null
    and (.packages | index("libayatana-appindicator")) != null
' >/dev/null <<< "${arch_json}"

cat > "${test_root}/arch-like" <<'EOF'
NAME="Arch-derived test system"
ID=example
ID_LIKE="arch"
PRETTY_NAME="Example Linux"
EOF
arch_like_json="$(platform_info "${test_root}/arch-like")"
jq -e '.id == "example" and .family == "arch"' >/dev/null <<< "${arch_like_json}"

cat > "${test_root}/unsupported" <<'EOF'
NAME="Future Linux"
ID=future
ID_LIKE="futurebase"
PRETTY_NAME="Future Linux 1"
EOF
unsupported_json="$(platform_info "${test_root}/unsupported")"
jq -e '
    .family == ""
    and .label == "Future Linux 1"
    and .automatic == false
    and .package_manager == ""
    and .packages == []
' >/dev/null <<< "${unsupported_json}"

cat > "${test_root}/hostile" <<'EOF'
ID="arch; touch /tmp/pdrive-platform-injection"
ID_LIKE="unknown"
EOF
hostile_json="$(platform_info "${test_root}/hostile")"
jq -e '.family == "" and .automatic == false' >/dev/null <<< "${hostile_json}"
[[ ! -e /tmp/pdrive-platform-injection ]]

printf 'PDrive distribution-adapter checks passed.\n'
