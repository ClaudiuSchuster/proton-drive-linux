#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-ui.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

PYTHONDONTWRITEBYTECODE=1 XDG_CONFIG_HOME="${test_root}/config" \
    python3 - "${project_dir}/bin/pdrive-ui" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import sys

loader = importlib.machinery.SourceFileLoader("pdrive_ui_test", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

assert module.load_preferences() == {
    "close_to_tray": False,
    "start_in_tray": False,
    "language": "en",
}
assert module.translate("Preferences") == "Preferences"
module.CURRENT_LANGUAGE = "de"
assert module.translate("Preferences") == "Einstellungen"
assert module.translate("Keep running in the tray when the window closes").startswith("Beim Schließen")
module.CURRENT_LANGUAGE = "en"

module.PDriveApplication.sync_autostart(True)
autostart = module.autostart_path()
assert autostart.exists()
assert "Exec=pdrive-ui --background" in autostart.read_text(encoding="utf-8")
assert module.AUTOSTART_MARKER in autostart.read_text(encoding="utf-8")

module.atomic_write(
    module.preferences_path(),
    json.dumps({"close_to_tray": False, "start_in_tray": True, "language": "de"}),
    0o600,
)
assert module.load_preferences() == {
    "close_to_tray": True,
    "start_in_tray": True,
    "language": "de",
}
assert module.preferences_path().stat().st_mode & 0o777 == 0o600

module.PDriveApplication.sync_autostart(False)
assert not autostart.exists()

autostart.parent.mkdir(parents=True, exist_ok=True)
autostart.write_text("[Desktop Entry]\nExec=some-other-app\n", encoding="utf-8")
try:
    module.PDriveApplication.sync_autostart(True)
except OSError as error:
    assert "Refusing to overwrite an unmarked autostart file" in str(error)
else:
    raise AssertionError("foreign autostart file was overwritten")
assert "some-other-app" in autostart.read_text(encoding="utf-8")
PY

printf 'PDrive UI preference checks passed.\n'
