#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d /tmp/proton-drive-linux-ui.XXXXXX)"
cleanup() { rm -rf -- "${test_root}"; }
trap cleanup EXIT

PYTHONDONTWRITEBYTECODE=1 \
    XDG_CONFIG_HOME="${test_root}/config" \
    XDG_DATA_HOME="${test_root}/data" \
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
    "issues_reviewed_errors": -1,
    "issues_reviewed_notices": -1,
    "issues_reviewed_at": "",
    "window_width": 1120,
    "window_height": 932,
}
assert module.translate("Preferences") == "Preferences"
assert module.translate("Documentation …") == "Documentation …"
module.CURRENT_LANGUAGE = "de"
assert module.translate("Preferences") == "Einstellungen"
assert module.translate("Documentation …") == "Handbuch …"
assert module.translate("Keep running in the tray when the window closes").startswith("Beim Schließen")
module.CURRENT_LANGUAGE = "en"
assert module.documentation_path("README.md", "README.md") == pathlib.Path(sys.argv[1]).resolve().parent.parent.joinpath("README.md")
blocks = module.markdown_blocks("# Title\n\nA **bold** [link](README.md).\n\n- item\n\n```\ncode\n```")
assert ("heading-1", "Title") in blocks
assert ("bullet", "item") in blocks
assert ("code", "code") in blocks

module.PDriveApplication.sync_autostart(True)
autostart = module.autostart_path()
assert autostart.exists()
assert "Exec=pdrive-ui --background" in autostart.read_text(encoding="utf-8")
assert module.AUTOSTART_MARKER in autostart.read_text(encoding="utf-8")

module.atomic_write(
    module.preferences_path(),
    json.dumps(
        {
            "close_to_tray": False,
            "start_in_tray": True,
            "language": "de",
            "issues_reviewed_errors": 40,
            "issues_reviewed_notices": 9,
            "issues_reviewed_at": "2026-08-24T12:00:00+02:00",
            "window_width": 1180,
            "window_height": 860,
        }
    ),
    0o600,
)
assert module.load_preferences() == {
    "close_to_tray": True,
    "start_in_tray": True,
    "language": "de",
    "issues_reviewed_errors": 40,
    "issues_reviewed_notices": 9,
    "issues_reviewed_at": "2026-08-24T12:00:00+02:00",
    "window_width": 1180,
    "window_height": 860,
}
assert module.preferences_path().stat().st_mode & 0o777 == 0o600

reviewed = module.load_preferences()
assert module.issues_since_review(reviewed, {"errors": 45, "notices": 11}) == (5, 2)
assert module.issues_since_review(reviewed, {"errors": 3, "notices": 2}) == (3, 2)
assert module.issues_since_review(module.DEFAULT_PREFERENCES, {"errors": 99, "notices": 8}) == (0, 0)

application = module.PDriveApplication()
assert application.update_preferences(False, False, "en") is None
updated = module.load_preferences()
assert updated["issues_reviewed_errors"] == 40
assert updated["issues_reviewed_notices"] == 9
assert updated["issues_reviewed_at"] == "2026-08-24T12:00:00+02:00"
assert updated["window_width"] == 1180
assert updated["window_height"] == 860
assert application.update_window_size(1040, 780) is None
resized = module.load_preferences()
assert resized["window_width"] == 1040
assert resized["window_height"] == 780
assert application.mark_issues_reviewed(
    {
        "errors": 45,
        "notices": 12,
        "generated_at": "2026-08-24T13:30:00+02:00",
    }
) is None
reviewed_again = module.load_preferences()
assert reviewed_again["issues_reviewed_errors"] == 45
assert reviewed_again["issues_reviewed_notices"] == 12
assert reviewed_again["issues_reviewed_at"] == "2026-08-24T13:30:00+02:00"

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
