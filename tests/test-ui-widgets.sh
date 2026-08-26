#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

runner=()
if [[ "${1:-}" == "--use-display" ]]; then
    :
elif command -v xvfb-run >/dev/null 2>&1; then
    runner=(xvfb-run -a)
else
    printf 'xvfb-run not installed; GTK widget checks skipped.\n' >&2
    exit 0
fi

PYTHONDONTWRITEBYTECODE=1 "${runner[@]}" \
    python3 - "${project_dir}/bin/pdrive-ui" <<'PY'
import importlib.machinery
import importlib.util
import copy
import sys
import time

loader = importlib.machinery.SourceFileLoader("pdrive_ui_widget_test", sys.argv[1])
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

app = module.PDriveApplication(demo=True)
assert app.register(None)
app.activate()
window = app.window
assert window is not None
assert window.get_default_size() == (module.DEFAULT_WINDOW_WIDTH, module.DEFAULT_WINDOW_HEIGHT)

def descendants(widget):
    yield widget
    if isinstance(widget, module.Gtk.Container):
        for child in widget.get_children():
            yield from descendants(child)

menu_buttons = [
    widget
    for widget in descendants(window.get_titlebar())
    if isinstance(widget, module.Gtk.MenuButton)
]
assert len(menu_buttons) == 1
header = window.get_titlebar()
assert isinstance(header, module.Gtk.HeaderBar)
assert header.get_show_close_button()
header_buttons = [
    widget
    for widget in descendants(header)
    if isinstance(widget, module.Gtk.Button)
]
header_actions = {
    button.get_tooltip_text(): button
    for button in header_buttons
    if button.get_tooltip_text()
}
for tooltip in (
    "Open /pdrive in Nemo",
    "Open Proton Drive on the web",
    "Refresh now",
    "Controls",
):
    assert tooltip in header_actions
for tooltip in ("Open /pdrive in Nemo", "Open Proton Drive on the web"):
    assert header.child_get_property(header_actions[tooltip], "pack-type") == module.Gtk.PackType.START
for tooltip in ("Refresh now", "Controls"):
    assert header.child_get_property(header_actions[tooltip], "pack-type") == module.Gtk.PackType.END
for decoration_layout in ("close,maximize,minimize:", ":minimize,maximize,close"):
    header.set_decoration_layout(decoration_layout)
    while module.Gtk.events_pending():
        module.Gtk.main_iteration_do(False)
    assert header.get_decoration_layout() == decoration_layout
    assert all(action.get_visible() for action in header_actions.values())
window_labels = [
    widget.get_text()
    for widget in descendants(window)
    if isinstance(widget, module.Gtk.Label)
]
assert "Open PDrive folder" in window_labels
assert "Open Proton Drive web" in window_labels
assert "Local VFS cache" in window_labels
assert window.open_web_button.get_style_context().has_class("secondary-web-action")
assert not window.open_web_button.get_style_context().has_class("primary-folder-action")
assert window.open_folder_button.get_style_context().has_class("primary-folder-action")
assert window.stack_switcher.get_style_context().has_class("pdrive-tabs")
assert len(window.stack_switcher.get_children()) == 3
assert all(button.get_tooltip_text() for button in window.stack_switcher.get_children())
assert all(
    button.get_events() & module.Gdk.EventMask.ENTER_NOTIFY_MASK
    for button in (window.open_web_button, window.open_folder_button, *window.stack_switcher.get_children())
)
assert set(window.config_buttons) == {"bandwidth", "slots", "metadata", "cooldown"}
assert all(button.get_sensitive() for button in window.config_buttons.values())
assert all(button.get_style_context().has_class("config-action") for button in window.config_buttons.values())
assert all(button.get_tooltip_text() for button in window.config_buttons.values())
assert set(window.config_value_size_group.get_widgets()) == set(window.config_labels.values())
popover = menu_buttons[0].get_popover()
assert popover is not None
assert popover.get_child() is not None
assert popover.get_child().get_visible()
assert not menu_buttons[0].get_active()
assert not popover.get_visible()

popover_buttons = [
    widget
    for widget in descendants(popover.get_child())
    if isinstance(widget, module.Gtk.Button)
]
assert len(popover_buttons) == 12
assert all(button.get_visible() for button in popover_buttons)
assert all(button.get_sensitive() for button in popover_buttons)
assert all(button.get_tooltip_text() for button in popover_buttons)
assert all(
    button.get_events() & module.Gdk.EventMask.ENTER_NOTIFY_MASK
    for button in popover_buttons
)
popover_labels = [
    widget.get_text()
    for widget in descendants(popover.get_child())
    if isinstance(widget, module.Gtk.Label)
]
assert "Documentation …" in popover_labels
assert "Open Proton Drive on the web" in popover_labels
assert "About …" in popover_labels
for configuration_action in (
    "Bandwidth limit …",
    "Upload slots …",
    "Cache retention …",
    "Metadata cache …",
    "Restart cooldown …",
):
    assert configuration_action in popover_labels

def button_with_label(text):
    return next(
        button
        for button in popover_buttons
        if text
        in [
            widget.get_text()
            for widget in descendants(button)
            if isinstance(widget, module.Gtk.Label)
        ]
    )

documentation_button = button_with_label("Documentation …")
assert documentation_button.get_sensitive()
assert button_with_label("Preferences …").get_sensitive()
about_button = button_with_label("About …")
assert about_button.get_sensitive()
menu_buttons[0].set_active(True)
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert popover.get_visible()
about_button.clicked()
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert not popover.get_visible()
assert not menu_buttons[0].get_active()
about_dialog = window.about_dialog
assert isinstance(about_dialog, module.Gtk.AboutDialog)
assert about_dialog.get_program_name() == "PDrive Control Center"
assert about_dialog.get_version() == module.VERSION
assert about_dialog.get_website() == module.PROJECT_URL
assert about_dialog.get_website_label() == "GitHub project"
assert about_dialog.get_license_type() == module.Gtk.License.GPL_3_0
assert about_dialog.get_style_context().has_class("pdrive-about")
assert b".pdrive-about *:link" in module.CSS
assert about_dialog.get_authors() == [
    "Claudiu Schuster — creator and maintainer\nhttps://github.com/ClaudiuSchuster",
    "OpenAI Codex — design and engineering collaborator\nhttps://github.com/openai/codex",
    "Fabian Schneider — comic relief, lively development chats and plenty of screenshots\n"
    "https://github.com/Fabian123333",
]
assert about_dialog.get_comments().startswith("We — Claudiu & Codex — loved turning")
assert "use.\n\nMade with love" in about_dialog.get_comments()
assert "Made with love for people on this beautiful world" in about_dialog.get_comments()
about_buttons = [
    widget
    for widget in descendants(about_dialog)
    if isinstance(widget, module.Gtk.Button)
]
credits_button = next(
    button
    for button in about_buttons
    if (button.get_label() or "").replace("_", "").casefold() == "credits"
)
credits_button.clicked()
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
credit_buttons = [
    widget
    for widget in descendants(about_dialog)
    if isinstance(widget, module.Gtk.Button)
    and widget.get_style_context().has_class("pdrive-about-credit")
]
assert len(credit_buttons) == 3
assert {button.get_tooltip_text() for button in credit_buttons} == {
    url for _description, url in module.ABOUT_CREDITS
}
assert all(button.get_sensitive() and button.get_visible() for button in credit_buttons)
assert all(button.get_halign() == module.Gtk.Align.START for button in credit_buttons)
assert all(button.get_events() & module.Gdk.EventMask.ENTER_NOTIFY_MASK for button in credit_buttons)
credit_urls = {url for _description, url in module.ABOUT_CREDITS}
assert all(
    not (
        label.get_use_markup()
        and any(f'href="{url}"' in label.get_label() for url in credit_urls)
    )
    for label in descendants(about_dialog)
    if isinstance(label, module.Gtk.Label)
)
license_buttons = [
    button
    for button in about_buttons
    if (button.get_label() or "").replace("_", "").casefold() in {"license", "lizenz"}
]
assert len(license_buttons) == 1
license_button = license_buttons[0]
license_button.clicked()
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert window.about_dialog is None
license_window = window.documentation_window
assert isinstance(license_window, module.DocumentationWindow)
assert license_window.stack.get_visible_child_name() == "license"
license_page = license_window.stack.get_child_by_name("license")
assert license_page.text_view.get_events() & module.Gdk.EventMask.POINTER_MOTION_MASK
license_text = license_page.buffer.get_text(
    license_page.buffer.get_start_iter(),
    license_page.buffer.get_end_iter(),
    True,
)
assert "GNU GENERAL PUBLIC LICENSE" in license_text
license_end = license_page.buffer.get_end_iter()
assert license_end.backward_char()
assert all(
    active_tag != link_tag
    for active_tag in license_end.get_tags()
    for link_tag, _target in license_page.link_tags
)
license_window.destroy()
assert window.documentation_window is None
assert window.problem_card.get_tooltip_text() == "Review issue details"
assert window.mark_issues_reviewed_button.get_label() == "Mark issues reviewed"

window.apply_state(module.demo_state())
window.apply_state(module.demo_state())
window.apply_state(module.demo_state())
assert window.speed_graph.get_size_request()[1] == 112
assert window.download_graph.get_size_request()[1] == 112
assert "MiB/s" in window.download_graph_peak.get_text()
assert "MiB/s" in window.download_speed_card.value.get_text()
assert window.download_speed_card.detail.get_text() == "Includes Proton API replies"
assert window.upload_graph_detail.get_text().endswith("every 2s")
assert window.download_graph_detail.get_text() == window.upload_graph_detail.get_text()
assert window.speed_graph.axis_labels[0].get_text().endswith("/s")
assert window.speed_graph.axis_labels[1].get_text().endswith("/s")
assert window.speed_graph.axis_labels[2].get_text() == "0 B/s"
assert window.speed_graph.timeline_start.get_text() == "~5m"
assert window.overview_grid.get_child_at(1, 0) is window.download_speed_card
assert window.overview_grid.get_child_at(2, 1) is window.capacity_card
assert window.overview_grid.get_column_spacing() == module.OVERVIEW_GUTTER
assert window.overview_grid.get_row_spacing() == module.OVERVIEW_GUTTER
assert window.activity_grid.get_column_spacing() == module.OVERVIEW_GUTTER
assert window.capacity_card.frame.get_style_context().has_class("overview-secondary")
assert window.activity_grid.get_child_at(0, 0) is window.active_card
assert window.activity_grid.get_child_at(1, 0) is window.queue_card
assert "free" in window.capacity_card.remote_value.get_text()
assert "used" in window.capacity_card.remote_detail.get_text()
assert "free" in window.capacity_card.local_value.get_text()
assert "VFS cache used" in window.capacity_card.local_detail.get_text()
assert "pending upload" in window.cache_card.detail.get_text()
assert "≈" in window.queue_card.detail.get_text()
assert "calculating" not in window.queue_card.detail.get_text()

recovery_state = copy.deepcopy(module.demo_state())
recovery_active = recovery_state["transfers"]["active"][0]
recovery_active["speed"] = 897.4 * 1024
recovery_active["eta_seconds"] = 9_223_372_036
recovery_state["queue"].update(
    {
        "count": 1,
        "active": 1,
        "failed": 1,
        "max_tries": 2,
        "bytes": recovery_active["size"],
        "remaining_bytes": recovery_active["size"] - recovery_active["bytes"],
        "items": [
            {
                "name": recovery_active["name"],
                "size": recovery_active["size"],
                "tries": 2,
                "uploading": True,
            }
        ],
    }
)
recovery_state["health"].update(
    {
        "status": "warning",
        "reason_code": "persistent-upload-failure",
        "summary": "At least one file remains queued after multiple upload attempts.",
    }
)
recovery_state["network_io"]["send_speed"] = 4 * 1024 * 1024
for _sample in range(3):
    window.apply_state(recovery_state)
assert window.status_title.get_text() == "Recovering"
assert window.status_frame.get_style_context().has_class("status-working")
assert "verified process traffic" in window.status_summary.get_text()
queue_eta = window.queue_card.detail.get_text().split("≈", 1)[1]
active_labels = [
    widget.get_text()
    for widget in descendants(window.active_list)
    if isinstance(widget, module.Gtk.Label)
]
assert "4.0 MiB/s" in active_labels
active_detail = next(text for text in active_labels if "· ≈" in text)
assert active_detail.endswith(queue_eta), (active_detail, queue_eta)
assert not any("897.4 KiB/s" in text for text in active_labels)
assert "ETA ≈" in window.queue_card.detail.get_tooltip_text()

stalled_state = copy.deepcopy(recovery_state)
stalled_state["network_io"]["send_speed"] = 0
window.upload_eta_last_progress = time.monotonic() - 31
window.apply_state(stalled_state)
assert window.status_title.get_text() == "Attention"
assert "⏸ ETA waiting" in window.queue_card.detail.get_text()
stalled_labels = [
    widget.get_text()
    for widget in descendants(window.active_list)
    if isinstance(widget, module.Gtk.Label)
]
assert "0 B/s" in stalled_labels
assert any("⏸ ETA waiting" in text for text in stalled_labels)

window.upload_eta_pid = 0
window.upload_eta_signature = ()
window.upload_eta_samples = 0
window.upload_eta_rate = 0
window.upload_eta_last_progress = 0
window.apply_state(recovery_state)
assert window.status_title.get_text() == "Attention"

critical_state = copy.deepcopy(recovery_state)
critical_state["health"].update(
    {
        "status": "critical",
        "reason_code": "service-inactive",
        "summary": "The Proton Drive service is inactive.",
    }
)
window.apply_state(critical_state)
window.apply_state(critical_state)
window.apply_state(critical_state)
assert window.status_title.get_text() == "Problem"

stress_state = copy.deepcopy(module.demo_state())
stress_state["queue"].update(
    {
        "count": 12_345,
        "active": 8,
        "bytes": 12 * 1024**4,
        "remaining_bytes": 12 * 1024**4,
    }
)
stress_state["network_io"]["send_speed"] = 20 * 1024
stress_state["configuration"]["running_transfers"] = 8
window.apply_state(stress_state)
window.apply_state(stress_state)
window.apply_state(stress_state)
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert window.queue_card.value.get_text() == "12345"
assert not window.queue_card.value.get_layout().is_ellipsized()
queue_stress_detail = window.queue_card.detail.get_text()
assert "12.0 TiB" in queue_stress_detail, queue_stress_detail
assert "≈" in queue_stress_detail, queue_stress_detail
assert not window.queue_card.detail.get_layout().is_ellipsized(), (
    queue_stress_detail,
    window.queue_card.detail.get_allocated_width(),
)
assert queue_stress_detail.endswith("d"), queue_stress_detail
assert "ETA ≈" in window.queue_card.detail.get_tooltip_text()
assert window.retention_button.get_sensitive()
assert window.retention_button.get_tooltip_text() == "Change cache retention"
assert window.retention_button.get_events() & module.Gdk.EventMask.ENTER_NOTIFY_MASK
assert all(value.get_text() != "–" for value in window.live_detail_labels.values())
assert "queued" in window.live_detail_labels["upload"].get_text()
assert "rclone process" in window.live_detail_labels["download"].get_text()
assert "synced read cache" in window.live_detail_labels["cache"].get_text()
assert "free of" in window.live_detail_labels["cloud"].get_text()
assert "uptime" in window.live_detail_labels["service"].get_text()
assert "DNS ok" in window.live_detail_labels["network"].get_text()
assert "TCP established" in window.live_detail_labels["network"].get_text()
assert window.service_detail_values["state"].get_text() == "active/running"
assert window.service_detail_values["process"].get_text() == "PID 4242 · result success · exit 0"
assert window.service_detail_values["uptime"].get_text() == "1d 3h"
assert window.service_detail_values["restarts"].get_text() == "0"
assert "ready" in window.service_detail_values["mount"].get_text()
assert "stall confirmation" in window.service_detail_values["watchdog"].get_text()
assert all(value.get_xalign() == 0.5 for value in window.config_labels.values())
assert window.live_summary.get_selectable()
assert window.live_summary_icon.get_icon_name()[0] == "emblem-synchronizing-symbolic"
assert all(value.get_selectable() for value in window.live_detail_labels.values())
assert window.copy_short_status_button.get_tooltip_text() == "Copy short status"
assert "PDrive Control Center — Ready" in window.short_status_text
assert "Configuration:" in window.short_status_text
app.update_indicator(window.current_state, 0)
assert app.status_icon is None or "0 B/s" in app.status_icon.get_tooltip_text()
assert len(window.issue_list.get_children()) == 5
assert not window.mark_issues_reviewed_button.get_sensitive()
assert isinstance(window.problem_card, module.Gtk.EventBox)
assert window.problem_card.get_above_child()
problem_frame_context = window.problem_card.frame.get_style_context()
assert not problem_frame_context.has_class("card-hover")
assert not problem_frame_context.has_class("card-pressed")
window.problem_card.on_pointer_enter(window.problem_card, None)
assert problem_frame_context.has_class("card-hover")
assert window.problem_card.get_window().get_cursor() is not None
press = type("PointerEvent", (), {"button": 1})()
window.problem_card.on_button_press(window.problem_card, press)
assert problem_frame_context.has_class("card-pressed")
window.problem_card.on_pointer_leave(window.problem_card, None)
assert not problem_frame_context.has_class("card-hover")
assert not problem_frame_context.has_class("card-pressed")
assert window.problem_card.get_window().get_cursor() is None
issue_click = module.Gdk.Event.new(module.Gdk.EventType.BUTTON_RELEASE)
issue_click.button = 1
issue_click.window = window.problem_card.get_window()
assert window.problem_card.emit("button-release-event", issue_click)
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert window.stack.get_visible_child_name() == "history"
assert window.cache_status_title.get_text() == "Uploads are still pending"
assert "2 clean file(s)" in window.cache_detail_values["clean"].get_text()
assert "3 pending file(s)" in window.cache_detail_values["pending"].get_text()
assert isinstance(window.cache_card, module.Gtk.EventBox)
assert window.cache_card.get_above_child()
assert window.cache_card.get_window() is not None
click = module.Gdk.Event.new(module.Gdk.EventType.BUTTON_RELEASE)
click.button = 1
click.window = window.cache_card.get_window()
assert window.cache_card.emit("button-release-event", click)
window.resize(900, 620)
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert window.stack.get_visible_child_name() == "transfers"
window.scroll_to_transfer_section("cache")
adjustment = window.transfers_scroller.get_vadjustment()
assert adjustment.get_value() > 0 or adjustment.get_upper() <= adjustment.get_page_size()
window.show_transfer_section("active")

documentation_button.emit("clicked")
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
documentation_windows = [
    candidate
    for candidate in app.get_windows()
    if isinstance(candidate, module.DocumentationWindow)
]
assert len(documentation_windows) == 1
documentation_window = documentation_windows[0]
assert len(documentation_window.stack.get_children()) == 5
guide = documentation_window.stack.get_child_by_name("guide")
assert guide is not None
guide_text = guide.text_view.get_buffer().get_text(
    guide.text_view.get_buffer().get_start_iter(),
    guide.text_view.get_buffer().get_end_iter(),
    True,
)
assert "Proton Drive Linux Mount Toolkit" in guide_text
assert "IMPORTANT" in guide_text
assert "independent community project" in guide_text
assert "<img" not in guide_text
assert "[!IMPORTANT]" not in guide_text
assert len(guide.rendered_images) == 5
assert guide.rendered_images[0].name == "io.github.claudiuschuster.PDriveControl.svg"
assert guide.rendered_images[-1].name == "pdrive-control-menu.png"
operations = documentation_window.stack.get_child_by_name("operations")
assert operations is not None
operations_text = operations.text_view.get_buffer().get_text(
    operations.text_view.get_buffer().get_start_iter(),
    operations.text_view.get_buffer().get_end_iter(),
    True,
)
for documented_control in (
    "Control Center settings reference",
    "Keep running in tray on window close",
    "Live metrics interval",
    "Metadata cache",
    "Cache retention",
    "Reset restart cooldown",
    "Safely restart service",
):
    assert documented_control in operations_text
security = documentation_window.stack.get_child_by_name("security")
assert security is not None
security_text = security.text_view.get_buffer().get_text(
    security.text_view.get_buffer().get_start_iter(),
    security.text_view.get_buffer().get_end_iter(),
    True,
)
normalized_security_text = " ".join(security_text.split())
for security_boundary in (
    "Reporting a vulnerability",
    "anonymous stdin pipes",
    "owner-only Unix socket",
    "Out of scope and inherited risk",
):
    assert security_boundary in normalized_security_text, security_boundary
documentation_window.destroy()

original_dialog_run = module.Gtk.Dialog.run

def inspect_preferences_dialog(dialog):
    save_button = dialog.get_widget_for_response(module.Gtk.ResponseType.OK)
    assert not save_button.get_sensitive()
    toggles = [
        widget
        for widget in descendants(dialog)
        if isinstance(widget, module.Gtk.CheckButton)
    ]
    background_toggle = next(
        toggle
        for toggle in toggles
        if toggle.get_label() == "Keep live metrics updating while hidden in the tray"
    )
    background_toggle.set_active(True)
    assert save_button.get_sensitive()
    background_toggle.set_active(False)
    assert not save_button.get_sensitive()
    combos = [
        widget
        for widget in descendants(dialog)
        if isinstance(widget, module.Gtk.ComboBoxText)
    ]
    interval_combo = next(combo for combo in combos if combo.get_active_id() == "2")
    notification_combo = next(combo for combo in combos if combo.get_active_id() == "important")
    language_combo = next(combo for combo in combos if combo.get_active_id() == "en")
    interval_combo.set_active_id("5")
    assert save_button.get_sensitive()
    interval_combo.set_active_id("2")
    assert not save_button.get_sensitive()
    language_combo.set_active_id("de")
    assert save_button.get_sensitive()
    language_combo.set_active_id("en")
    assert not save_button.get_sensitive()
    notification_combo.set_active_id("critical")
    assert save_button.get_sensitive()
    notification_combo.set_active_id("important")
    assert not save_button.get_sensitive()
    return module.Gtk.ResponseType.CANCEL

module.Gtk.Dialog.run = inspect_preferences_dialog
try:
    window.on_preferences(None)
finally:
    module.Gtk.Dialog.run = original_dialog_run

opened_configuration_dialogs = []

def inspect_configuration_dialog(dialog):
    opened_configuration_dialogs.append(dialog.get_title())
    save_button = dialog.get_widget_for_response(module.Gtk.ResponseType.OK)
    assert not save_button.get_sensitive()
    if dialog.get_title() in {"Metadata cache", "Restart cooldown"}:
        assert dialog.get_content_area().get_size_request()[0] == 440
    return module.Gtk.ResponseType.CANCEL

module.Gtk.Dialog.run = inspect_configuration_dialog
try:
    for config_button in window.config_buttons.values():
        config_button.emit("clicked")
finally:
    module.Gtk.Dialog.run = original_dialog_run
assert opened_configuration_dialogs == [
    "Bandwidth limit",
    "Upload slots",
    "Metadata cache",
    "Restart cooldown",
]

assert module.tray_supports_distinct_clicks()


class FixedAdjustment:
    @staticmethod
    def get_upper():
        return 820

    @staticmethod
    def get_page_size():
        return 720


class FixedScroller:
    @staticmethod
    def get_vadjustment():
        return FixedAdjustment()


class ContentFitTracker:
    closed = False
    setup_required = False
    current_state = {"health": {"status": "ready"}}
    content_fit_source = 1
    content_fit_completed = False
    overview_scroller = FixedScroller()
    root = None

    def __init__(self):
        self.resizes = []

    @staticmethod
    def get_visible():
        return True

    @staticmethod
    def get_mapped():
        return True

    @staticmethod
    def get_size():
        return (820, 720)

    @staticmethod
    def get_window():
        return None

    def resize(self, width, height):
        self.resizes.append((width, height))


fit_tracker = ContentFitTracker()
assert module.PDriveWindow.fit_content_height(fit_tracker) == module.GLib.SOURCE_REMOVE
assert fit_tracker.resizes == [(820, 824)]
assert fit_tracker.content_fit_completed
# Reusing the stale adjustment cannot compound the first resize.
fit_tracker.content_fit_source = 1
assert module.PDriveWindow.fit_content_height(fit_tracker) == module.GLib.SOURCE_REMOVE
assert fit_tracker.resizes == [(820, 824)]

app.demo = False
window.demo = False
refreshes = []
window.request_refresh = lambda: refreshes.append(True)
window.hide()
window.content_fit_source = 1
assert window.fit_content_height() == module.GLib.SOURCE_REMOVE
assert window.content_fit_source == 0
app.preferences["poll_in_background"] = False
assert window.on_refresh_timer() == module.GLib.SOURCE_CONTINUE
assert refreshes == []
app.preferences["poll_in_background"] = True
window.on_refresh_timer()
assert len(refreshes) == 1
app.preferences["poll_in_background"] = False
window.show_all()
window.on_refresh_timer()
assert len(refreshes) == 2
app.preferences["close_to_tray"] = True
app.configure_tray()
assert app.status_icon is not None
assert app.indicator is None
app.preferences["close_to_tray"] = False
app.preferences["start_in_tray"] = False
app.configure_tray()
assert not app.status_icon.get_visible()
app.demo = True
window.demo = True

menu_buttons[0].set_active(True)
while module.Gtk.events_pending():
    module.Gtk.main_iteration_do(False)
assert menu_buttons[0].get_active()
assert popover.get_visible()
menu_buttons[0].set_active(False)

window.closed = True
window.destroy()
app.quit()
PY

printf 'PDrive GTK widget checks passed.\n'
