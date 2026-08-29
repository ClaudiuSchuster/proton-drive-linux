#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-setup-ui.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

runner=()
if [[ "${1:-}" == --use-display ]]; then
    :
elif command -v xvfb-run >/dev/null 2>&1; then
    runner=(xvfb-run -a)
else
    printf 'xvfb-run not installed; PDrive setup-wizard widget checks skipped.\n' >&2
    exit 0
fi

test_home="${test_root}/home"
mount_dir="${test_root}/mount"
config_file="${test_home}/.config/rclone/rclone.conf"
fake_setup="${test_root}/pdrive-setup"
fake_rclone="${test_root}/rclone-bin"
fake_network_tune="${test_root}/pdrive-network-tune"
fake_bwlimit="${test_root}/pdrive-bwlimit"
bandwidth_log="${test_root}/bandwidth.log"
mkdir -p -- "${test_home}" "${mount_dir}"

# Preserve the expansions for the fake process rather than this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'case "${1:-}" in' \
    '  version) printf "rclone v1.76.0-beta.10204.660144d31\n" ;;' \
    '  help) [[ "${2:-}" == backend && "${3:-}" == protondrive ]] ;;' \
    '  backend) [[ "${2:-}" == help && "${3:-}" == protondrive ]] && printf "### data-bandwidth\n" ;;' \
    '  *) exit 2 ;;' \
    'esac' > "${fake_rclone}"
chmod 0755 "${fake_rclone}"

# The single-quoted fixture lines must preserve their expansions for the fake
# setup process rather than evaluating them in this test process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '[[ "${1:-}" == --setup-from-stdin ]]' \
    'IFS= read -r -d "" username' \
    'IFS= read -r -d "" password' \
    'IFS= read -r -d "" two_factor' \
    '[[ "${username}" == person@example.test ]]' \
    '[[ "${password}" == "correct horse battery staple" ]]' \
    '[[ "${two_factor}" == 123456 ]]' \
    '[[ "${PDRIVE_TEST_SETUP_FAIL:-}" != 1 ]] || exit 42' \
    'mkdir -p -- "${PDRIVE_RCLONE_CONFIG%/*}"' \
    'printf "[proton]\\ntype = protondrive\\n" > "${PDRIVE_RCLONE_CONFIG}"' > "${fake_setup}"
chmod 0755 "${fake_setup}"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    '[[ "$*" == "measure --json" ]]' \
    'printf '\''{"upload":{"measured_mib_per_second":8,"recommended_mib_per_second":4.8},"download":{"measured_mib_per_second":20,"recommended_mib_per_second":12}}\n'\''' \
    > "${fake_network_tune}"
# Preserve the expansion for the fake helper process.
# shellcheck disable=SC2016
printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "${1:-}" >> "${PDRIVE_TEST_BANDWIDTH_LOG}"' \
    > "${fake_bwlimit}"
chmod 0755 "${fake_network_tune}" "${fake_bwlimit}"

HOME="${test_home}" \
    XDG_CONFIG_HOME="${test_home}/.config" \
    XDG_DATA_HOME="${test_home}/.local/share" \
    PDRIVE_MOUNT_DIR="${mount_dir}" \
    PDRIVE_RCLONE_CONFIG="${config_file}" \
    PDRIVE_REAL_RCLONE="${fake_rclone}" \
    PDRIVE_SETUP_BIN="${fake_setup}" \
    PDRIVE_NETWORK_TUNE_BIN="${fake_network_tune}" \
    PDRIVE_BWLIMIT_BIN="${fake_bwlimit}" \
    PDRIVE_TEST_BANDWIDTH_LOG="${bandwidth_log}" \
    PDRIVE_UI_NON_UNIQUE=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    "${runner[@]}" python3 - "${project_dir}/bin/pdrive-ui" <<'PY'
import importlib.machinery
import importlib.util
import pathlib
import sys
import time

loader = importlib.machinery.SourceFileLoader("pdrive_setup_ui_test", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)
module.REQUIRED_RUNTIME_COMMANDS = ()

app = module.PDriveApplication()
assert app.register(None)
app.activate()
window = app.window
assert window is not None
assert window.setup_required
wizard = window.setup_wizard
assert wizard is not None
assert wizard.readiness["ready"]
assert wizard.stack.get_visible_child_name() == "readiness"
rclone_fixture = pathlib.Path(module.os.environ["PDRIVE_REAL_RCLONE"])
safe_rclone = rclone_fixture.read_text(encoding="utf-8")
rclone_fixture.write_text(
    "#!/usr/bin/env bash\n"
    "case \"${1:-}\" in\n"
    "  version) printf 'rclone v1.75.0\\n' ;;\n"
    "  help) exit 0 ;;\n"
    "  backend) printf '### data-bandwidth\\n' ;;\n"
    "  *) exit 2 ;;\n"
    "esac\n",
    encoding="utf-8",
)
rclone_fixture.chmod(0o755)
wizard.refresh_readiness()
assert not wizard.readiness["ready"]
assert wizard.readiness["rclone_present"]
assert not wizard.readiness["rclone_ready"]
assert wizard.prepare_button.get_label() == "Reinstall recommended rclone"
assert wizard.prepare_button.get_tooltip_text() in {
    module.translate(
        "Only the user-local rclone binary is replaced; configuration, cache and mount data remain untouched."
    ),
    module.translate(
        "Automatic package installation is available on Debian, Ubuntu and Linux Mint systems with Polkit."
    ),
}
rclone_fixture.write_text(safe_rclone, encoding="utf-8")
rclone_fixture.chmod(0o755)
wizard.refresh_readiness()
assert wizard.readiness["ready"]

def drain_until(predicate):
    deadline = time.monotonic() + 5
    while not predicate() and time.monotonic() < deadline:
        while module.Gtk.events_pending():
            module.Gtk.main_iteration_do(False)
        time.sleep(0.01)
    assert predicate()

wizard.continue_button.emit("clicked")
assert wizard.stack.get_visible_child_name() == "bandwidth"
assert wizard.bandwidth_auto.get_active()
wizard.bandwidth_continue_button.emit("clicked")
drain_until(lambda: wizard.bandwidth_policy_ready and not wizard.bandwidth_preparing)
assert "4.80 / 12.00 MiB/s" in wizard.bandwidth_result.get_text()
bandwidth_log = pathlib.Path(module.os.environ["PDRIVE_TEST_BANDWIDTH_LOG"])
assert bandwidth_log.read_text(encoding="utf-8").splitlines() == ["4.80:12.00"]
wizard.bandwidth_continue_button.emit("clicked")
assert wizard.stack.get_visible_child_name() == "account"
assert len(
    [
        widget
        for widget in wizard.password_entry.get_parent().get_children()
        if isinstance(widget, module.Gtk.Entry)
    ]
) == 3

def submit():
    wizard.username_entry.set_text("person@example.test")
    wizard.password_entry.set_text("correct horse battery staple")
    wizard.two_factor_entry.set_text("123456")
    wizard.on_connect(module.Gtk.Button())
    assert wizard.password_entry.get_text() == ""
    assert wizard.two_factor_entry.get_text() == ""

module.os.environ["PDRIVE_TEST_SETUP_FAIL"] = "1"
submit()
drain_until(lambda: wizard.stack.get_visible_child_name() == "account" and not wizard.connecting)
assert wizard.account_error.get_visible()
assert not pathlib.Path(module.setup_config_path()).exists()

del module.os.environ["PDRIVE_TEST_SETUP_FAIL"]
submit()
drain_until(lambda: wizard.stack.get_visible_child_name() == "success")
assert pathlib.Path(module.setup_config_path()).is_file()

refreshes = []
window.request_refresh = lambda: refreshes.append(True)
window.enter_dashboard()
assert not window.setup_required
assert window.setup_wizard is None
assert window.stack.get_visible_child_name() == "overview"
assert refreshes == [True]

window.closed = True
window.destroy()
app.quit()
PY

printf 'PDrive setup-wizard widget checks passed.\n'
