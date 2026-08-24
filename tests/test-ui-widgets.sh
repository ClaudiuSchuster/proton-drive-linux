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
import sys

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
window_labels = [
    widget.get_text()
    for widget in descendants(window)
    if isinstance(widget, module.Gtk.Label)
]
assert "Open PDrive folder" in window_labels
assert "Local VFS cache" in window_labels
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
assert len(popover_buttons) == 7
assert all(button.get_visible() for button in popover_buttons)
popover_labels = [
    widget.get_text()
    for widget in descendants(popover.get_child())
    if isinstance(widget, module.Gtk.Label)
]
assert "Documentation …" in popover_labels

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
assert not button_with_label("Preferences …").get_sensitive()
assert window.issue_review_button.get_tooltip_text() == "Mark issues reviewed"

window.apply_state(module.demo_state())
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
assert len(documentation_window.stack.get_children()) == 3
guide = documentation_window.stack.get_child_by_name("guide")
assert guide is not None
guide_text = guide.text_view.get_buffer().get_text(
    guide.text_view.get_buffer().get_start_iter(),
    guide.text_view.get_buffer().get_end_iter(),
    True,
)
assert "Proton Drive Linux Mount Toolkit" in guide_text
documentation_window.destroy()

assert module.tray_supports_distinct_clicks()
app.demo = False
window.demo = False
refreshes = []
window.request_refresh = lambda: refreshes.append(True)
window.hide()
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
