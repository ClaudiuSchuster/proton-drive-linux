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
    "poll_in_background": False,
    "refresh_interval_seconds": 2,
    "language": "en",
    "issues_reviewed_errors": -1,
    "issues_reviewed_notices": -1,
    "issues_reviewed_at": "",
}
assert module.translate("Preferences") == "Preferences"
assert module.translate("Documentation …") == "Documentation …"
assert module.translate("About …") == "About …"
module.CURRENT_LANGUAGE = "de"
assert module.translate("Preferences") == "Einstellungen"
assert module.translate("Documentation …") == "Handbuch …"
assert module.translate("About …") == "Über …"
assert module.translate("GitHub project") == "GitHub-Projekt"
assert module.translate("License") == "Lizenz"
assert module.translate(
    "Fabian Schneider — comic relief, lively development chats and plenty of screenshot feedback"
).startswith("Fabian Schneider — Quatschkomödie")
assert module.translate("Keep running in the tray when the window closes").startswith("Beim Schließen")
assert module.translate("Keep live metrics updating while hidden in the tray").startswith("Live-Metriken")
module.CURRENT_LANGUAGE = "en"
assert module.documentation_path("README.md", "README.md") == pathlib.Path(sys.argv[1]).resolve().parent.parent.joinpath("README.md")
blocks = module.markdown_blocks(
    "<p align=\"center\">\n"
    "  <img src=\"icon.svg\"\n"
    "       width=\"112\" height=\"112\" alt=\"icon\">\n"
    "</p>\n\n"
    "# Title\n\n"
    "A **bold** [link](README.md).\n\n"
    "> [!IMPORTANT]\n"
    "> Keep an **independent backup**.\n\n"
    "- item\n\n"
    "```\ncode\n```"
)
assert ("heading-1", "Title") in blocks
assert ("bullet", "item") in blocks
assert ("code", "code") in blocks
assert ("admonition-important", "Keep an **independent backup**.") in blocks
image_blocks = [json.loads(text) for kind, text in blocks if kind == "image"]
assert image_blocks == [{"src": "icon.svg", "width": "112", "alt": "icon"}]
assert not any("<img" in text or "[!IMPORTANT]" in text for _, text in blocks)
table_blocks = module.markdown_blocks(
    "| Setting | Default |\n"
    "| --- | --- |\n"
    "| Cache retention | **24 hours** |\n"
)
assert table_blocks == [
    (
        "table-row",
        "**Setting:**\u2002Cache retention\n**Default:**\u2002**24 hours**",
    )
]

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
            "poll_in_background": True,
            "refresh_interval_seconds": 5,
            "language": "de",
            "issues_reviewed_errors": 40,
            "issues_reviewed_notices": 9,
            "issues_reviewed_at": "2026-08-24T12:00:00+02:00",
        }
    ),
    0o600,
)
assert module.load_preferences() == {
    "close_to_tray": True,
    "start_in_tray": True,
    "poll_in_background": True,
    "refresh_interval_seconds": 5,
    "language": "de",
    "issues_reviewed_errors": 40,
    "issues_reviewed_notices": 9,
    "issues_reviewed_at": "2026-08-24T12:00:00+02:00",
}
assert module.preferences_path().stat().st_mode & 0o777 == 0o600

reviewed = module.load_preferences()
assert module.issues_since_review(reviewed, {"errors": 45, "notices": 11}) == (5, 2)
assert module.issues_since_review(reviewed, {"errors": 3, "notices": 2}) == (3, 2)
assert module.issues_since_review(module.DEFAULT_PREFERENCES, {"errors": 99, "notices": 8}) == (0, 0)
issue_events = [
    {"timestamp": "1", "level": "error", "message": "old error"},
    {"timestamp": "2", "level": "notice", "message": "old notice"},
    {"timestamp": "3", "level": "error", "message": "new error"},
    {"timestamp": "4", "level": "notice", "message": "new notice"},
]
selected, missing = module.unreviewed_issue_events(
    reviewed,
    {"errors": 41, "notices": 10},
    {"available": True, "events": issue_events},
)
assert [event["message"] for event in selected] == ["new error", "new notice"]
assert missing == 0
selected, missing = module.unreviewed_issue_events(
    reviewed,
    {"errors": 45, "notices": 12},
    {"available": True, "events": issue_events[-1:]},
)
assert [event["message"] for event in selected] == ["new notice"]
assert missing == 7

rate, baseline = module.network_receive_rate(
    None,
    {"available": True, "received_bytes": 1_000_000},
    4242,
    10.0,
)
assert rate == 0
rate, baseline = module.network_receive_rate(
    baseline,
    {"available": True, "received_bytes": 5_194_304},
    4242,
    12.0,
)
assert rate == 2_097_152
rate, baseline = module.network_receive_rate(
    baseline,
    {"available": True, "received_bytes": 8_000_000},
    5252,
    14.0,
)
assert rate == 0
rate, baseline = module.network_receive_rate(
    baseline,
    {"available": False},
    5252,
    16.0,
)
assert rate == 0 and baseline is None

assert module.bandwidth_slider_position("off") == module.BANDWIDTH_SLIDER_UNLIMITED
assert module.bandwidth_slider_position("0") == module.BANDWIDTH_SLIDER_UNLIMITED
assert 60 < module.bandwidth_slider_position("4.200Mi:off") < 70
assert 40 < module.bandwidth_slider_position("800K:off") < 50
assert abs(module.bandwidth_slider_rate(module.bandwidth_slider_position("4.2")) - 4.2) < 0.001
assert module.bandwidth_slider_command(0) == "0.02"
assert module.bandwidth_slider_command(module.bandwidth_slider_position("4.2")) == "4.2"
assert module.bandwidth_slider_command(module.BANDWIDTH_SLIDER_UNLIMITED) == "off"
assert "≈0" in module.bandwidth_slider_label(0)
assert "4.2 MiB/s" in module.bandwidth_slider_label(module.bandwidth_slider_position("4.2"))
assert "off/0" in module.bandwidth_slider_label(module.BANDWIDTH_SLIDER_UNLIMITED)
assert module.argument_parser().parse_args(["--demo", "--demo-page", "history"]).demo_page == "history"

application = module.PDriveApplication()
assert application.update_preferences(False, False, False, 10, "en") is None
updated = module.load_preferences()
assert updated["poll_in_background"] is False
assert updated["refresh_interval_seconds"] == 10
assert updated["issues_reviewed_errors"] == 40
assert updated["issues_reviewed_notices"] == 9
assert updated["issues_reviewed_at"] == "2026-08-24T12:00:00+02:00"
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
