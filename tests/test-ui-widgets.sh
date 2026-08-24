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

assert button_with_label("Documentation …").get_sensitive()
assert not button_with_label("Preferences …").get_sensitive()
assert window.issue_review_button.get_tooltip_text() == "Mark issues reviewed"

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
