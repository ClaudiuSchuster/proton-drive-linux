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
    "notification_policy": "important",
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
assert module.translate("Quick start") == "Schnellstart"
assert module.translate("Everyday use") == "Tägliche Nutzung"
assert module.translate("Download limit in MiB/s") == "Downloadlimit in MiB/s"
assert module.translate("Upload retry is progressing") == "Upload-Wiederholungsversuch macht Fortschritt"
assert module.translate("Proton service recovered") == "Proton-Dienst wiederhergestellt"
assert module.translate("Proton session refresh was rejected") == (
    "Proton-Sitzungsaktualisierung wurde abgelehnt"
)
assert module.translate("Proton session refresh recovered") == (
    "Proton-Sitzungsaktualisierung wiederhergestellt"
)
assert module.translate(
    "No action is required while PDrive continues to report healthy authentication and mount state."
).startswith("Keine Aktion erforderlich")
assert module.translate(
    "Recent log contains {count} related records · oldest retained {time}"
).startswith("Aktuelles Protokoll")
assert module.translate(
    "The logarithmic sliders give low everyday limits more precision. Leaving connection headroom can keep browsing and calls responsive; use pdrive-bwlimit for values above 100 MiB/s."
).startswith("Die logarithmischen Regler")
assert module.translate(
    "Fabian Schneider — comic relief, lively development chats and plenty of screenshots"
).startswith("Fabian Schneider — Quatschkomödie")
assert module.translate("Keep running in the tray when the window closes").startswith("Beim Schließen")
assert module.translate("Keep live metrics updating while hidden in the tray").startswith("Live-Metriken")
assert module.translate("Change Proton account …") == "Proton-Konto wechseln …"
assert module.translate("Previous account restored") == "Vorheriges Konto wiederhergestellt"
module.CURRENT_LANGUAGE = "en"
project_root = pathlib.Path(sys.argv[1]).resolve().parent.parent
assert module.documentation_path("QUICK_START.md", "docs/QUICK_START.md") == project_root.joinpath(
    "docs/QUICK_START.md"
)
assert [page[0] for page in module.DOCUMENTATION_PAGES] == [
    "quick-start",
    "everyday-use",
    "operations",
    "troubleshooting",
    "security",
    "license",
]
assert module.DOCUMENTATION_PAGES[-1][-1] is True
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
long_line = "Apostrophe reader's line " + "x" * 4096
edge_blocks = module.markdown_blocks(
    f"{long_line}\n\nUse `inline code` and [a local link](EVERYDAY_USE.md).\n"
)
assert ("paragraph", long_line) in edge_blocks
assert any("`inline code`" in text and "[a local link]" in text for _, text in edge_blocks)

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
            "notification_policy": "critical",
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
    "notification_policy": "critical",
    "language": "de",
    "issues_reviewed_errors": 40,
    "issues_reviewed_notices": 9,
    "issues_reviewed_at": "2026-08-24T12:00:00+02:00",
}
assert module.preferences_path().stat().st_mode & 0o777 == 0o600

reviewed = module.load_preferences()
issue_events = [
    {"timestamp": "2026-08-24T11:00:00+02:00", "level": "error", "message": "old error"},
    {"timestamp": "2026-08-24T11:30:00+02:00", "level": "notice", "message": "old notice"},
    {"timestamp": "2026-08-24T13:00:00+02:00", "level": "error", "message": "new error"},
    {"timestamp": "2026-08-24T13:15:00+02:00", "level": "notice", "message": "new notice"},
    {
        "timestamp": "2026-08-24T13:30:00+02:00",
        "level": "notice",
        "lifecycle": "resolved",
        "message": "automatic recovery",
    },
]
issue_payload = {"available": True, "events": issue_events}
assert module.issues_since_review(reviewed, issue_payload) == (1, 1)
assert module.issues_since_review(module.DEFAULT_PREFERENCES, issue_payload) == (0, 0)
selected, missing = module.unreviewed_issue_events(
    reviewed,
    issue_payload,
)
assert [event["message"] for event in selected] == ["new error", "new notice"]
assert missing == 0
assert [event["message"] for event in module.resolved_events(issue_payload)] == ["automatic recovery"]
selected, missing = module.unreviewed_issue_events(
    reviewed,
    {"available": True, "events": issue_events[3:4]},
)
assert [event["message"] for event in selected] == ["new notice"]
assert missing == 0

rate, baseline = module.network_send_rate(
    None,
    {"available": True, "sent_bytes": 2_000_000},
    4242,
    10.0,
)
assert rate == 0
rate, baseline = module.network_send_rate(
    baseline,
    {"available": True, "sent_bytes": 10_388_608},
    4242,
    12.0,
)
assert rate == 4_194_304
rate, baseline = module.network_send_rate(
    baseline,
    {"available": True, "sent_bytes": 10_388_608},
    4242,
    14.0,
)
assert rate == 0

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


class EtaTracker:
    upload_eta_pid = 0
    upload_eta_rate = 0.0
    upload_eta_samples = 0
    upload_eta_last_progress = 0.0
    upload_eta_signature = ()
    upload_eta_seconds = -1

    @staticmethod
    def refresh_interval_seconds():
        return 2


eta_tracker = EtaTracker()
near_pause_queue = {"count": 1, "active": 1, "remaining_bytes": 20 * 1024 * 1024}
assert "calculating" in module.PDriveWindow.queue_eta_detail(
    eta_tracker, near_pause_queue, 20 * 1024, 4242, 10.0
)
module.PDriveWindow.queue_eta_detail(eta_tracker, near_pause_queue, 20 * 1024, 4242, 12.0)
near_pause_eta = module.PDriveWindow.queue_eta_detail(
    eta_tracker, near_pause_queue, 20 * 1024, 4242, 14.0
)
assert "≈" in near_pause_eta
assert "calculating" not in near_pause_eta
assert module.compact_eta_duration(99 * 86400) == "99d 0h"
assert module.compact_eta_duration((100 * 86400) + 1) == "101d"
assert module.upload_eta_ready(3, 20 * 1024, 14.0, 14.0, 2)
assert not module.upload_eta_ready(2, 20 * 1024, 14.0, 14.0, 2)
assert not module.upload_eta_ready(3, 20 * 1024, 14.0, 45.0, 2)

waiting_tracker = EtaTracker()
waiting_eta = module.PDriveWindow.queue_eta_detail(
    waiting_tracker, near_pause_queue, 0, 4242, 10.0
)
assert "⏸ ETA waiting" in waiting_eta

single_name = "demo/large.img"
single_queue = {
    "count": 1,
    "active": 1,
    "bytes": 20 * 1024 * 1024,
    "remaining_bytes": 10 * 1024 * 1024,
    "items": [{"name": single_name, "size": 20 * 1024 * 1024, "uploading": True}],
}
single_transfers = {
    "active": [
        {
            "name": single_name,
            "size": 20 * 1024 * 1024,
            "bytes": 10 * 1024 * 1024,
            "speed": 900 * 1024,
            "eta_seconds": 999999,
        }
    ]
}
single_metrics = module.verified_single_transfer_metrics(
    single_transfers,
    single_queue,
    20 * 1024,
    20 * 1024,
    True,
)
assert single_metrics == {"speed": 20 * 1024, "eta_seconds": 512, "estimate_ready": True}
assert module.backend_transfer_metrics(single_transfers["active"][0]) == (0.0, -1)
assert module.backend_transfer_metrics({**single_transfers["active"][0], "eta_seconds": 0}) == (0.0, -1)
assert module.verified_single_transfer_metrics(
    {"active": single_transfers["active"] * 2},
    {**single_queue, "count": 2},
    20 * 1024,
    20 * 1024,
    True,
) is None

identity_tracker = EtaTracker()
for sample_time in (10.0, 12.0, 14.0):
    module.PDriveWindow.queue_eta_detail(identity_tracker, single_queue, 20 * 1024, 4242, sample_time)
assert identity_tracker.upload_eta_samples == 3
changed_queue = {
    **single_queue,
    "items": [{"name": "demo/replacement.img", "size": 20 * 1024 * 1024, "uploading": True}],
}
changed_detail = module.PDriveWindow.queue_eta_detail(identity_tracker, changed_queue, 20 * 1024, 4242, 16.0)
assert "calculating" in changed_detail
assert identity_tracker.upload_eta_samples == 1

assert module.bandwidth_slider_position("off") == module.BANDWIDTH_SLIDER_UNLIMITED
assert module.bandwidth_slider_position("0") == module.BANDWIDTH_SLIDER_UNLIMITED
assert 60 < module.bandwidth_slider_position("4.200Mi:off") < 70
assert module.bandwidth_slider_position("4.200Mi:off", "download") == module.BANDWIDTH_SLIDER_UNLIMITED
assert abs(module.bandwidth_slider_rate(module.bandwidth_slider_position("4.200Mi:1Mi", "download")) - 1) < 0.001
assert abs(module.bandwidth_slider_rate(module.bandwidth_slider_position("4.200Mi", "download")) - 4.2) < 0.001
assert 40 < module.bandwidth_slider_position("800K:off") < 50
assert abs(module.bandwidth_slider_rate(module.bandwidth_slider_position("4.2")) - 4.2) < 0.001
assert module.bandwidth_slider_command(0) == "0.02"
assert module.bandwidth_slider_command(module.bandwidth_slider_position("4.2")) == "4.2"
assert module.bandwidth_slider_command(module.BANDWIDTH_SLIDER_UNLIMITED) == "off"
assert module.bandwidth_slider_command(
    module.bandwidth_slider_position("4.2"), module.BANDWIDTH_SLIDER_UNLIMITED
) == "4.2:off"
assert module.bandwidth_slider_command(
    module.BANDWIDTH_SLIDER_UNLIMITED, module.bandwidth_slider_position("2")
) == "off:2"
assert module.bandwidth_slider_command(
    module.BANDWIDTH_SLIDER_UNLIMITED, module.BANDWIDTH_SLIDER_UNLIMITED
) == "off"
assert "≈0" in module.bandwidth_slider_label(0)
assert "4.2 MiB/s" in module.bandwidth_slider_label(module.bandwidth_slider_position("4.2"))
assert "off/0" in module.bandwidth_slider_label(module.BANDWIDTH_SLIDER_UNLIMITED)
assert module.argument_parser().parse_args(["--demo", "--demo-page", "history"]).demo_page == "history"

application = module.PDriveApplication()
assert application.update_preferences(False, False, False, 10, "all", "en") is None
updated = module.load_preferences()
assert updated["poll_in_background"] is False
assert updated["refresh_interval_seconds"] == 10
assert updated["notification_policy"] == "all"
assert updated["issues_reviewed_errors"] == 40
assert updated["issues_reviewed_notices"] == 9
assert updated["issues_reviewed_at"] == "2026-08-24T12:00:00+02:00"
assert application.mark_issues_reviewed(
    {
        "generated_at": "2026-08-24T13:30:00+02:00",
        "issues": {"errors": 2, "notices": 1},
    }
) is None
reviewed_again = module.load_preferences()
assert reviewed_again["issues_reviewed_errors"] == 2
assert reviewed_again["issues_reviewed_notices"] == 1
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
