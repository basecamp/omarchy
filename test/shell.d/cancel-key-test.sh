#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "shell"
util = (root / "Commons/Util.qml").read_text()
predicate = re.compile(
    r"function isCancelKey\(event\)\s*\{\s*"
    r"return event\.key === Qt\.Key_Escape\s*"
    r"\|\| \(event\.key === Qt\.Key_G\s*"
    r"&& event\.modifiers === Qt\.ControlModifier\)\s*\}",
    re.DOTALL,
)
if not predicate.search(util):
    print("shared cancel predicate no longer matches Escape and exact Ctrl+G", file=sys.stderr)
    raise SystemExit(1)
print("ok - shared cancel predicate matches Escape and exact Ctrl+G")

cancel_paths = [
    "Ui/ConfirmDialog.qml",
    "Ui/Dropdown.qml",
    "Ui/MultiSelect.qml",
    "Ui/PanelKeyCatcher.qml",
    "Ui/SearchableDropdown.qml",
    "Ui/SpeedTestOverlay.qml",
    "plugins/clipboard/Clipboard.qml",
    "plugins/dev-gallery/GalleryPanel.qml",
    "plugins/emojis/Emojis.qml",
    "plugins/image-picker/ImagePicker.qml",
    "plugins/lock/LockView.qml",
    "plugins/menu/Menu.qml",
    "plugins/panels/clock/Panel.qml",
    "plugins/panels/network/Panel.qml",
    "plugins/panels/tailscale/Panel.qml",
    "plugins/panels/weather/Panel.qml",
    "plugins/panels/wifiqr/Panel.qml",
    "plugins/polkit/PolkitAgent.qml",
    "plugins/reminders/ReminderFlow.qml",
]

for relative in cancel_paths:
    text = (root / relative).read_text()
    if "Util.isCancelKey(event)" not in text:
        print(f"shared cancel predicate missing from {relative}", file=sys.stderr)
        raise SystemExit(1)
    if "import qs.Commons" not in text:
        print(f"qs.Commons import missing from {relative}", file=sys.stderr)
        raise SystemExit(1)
    if "event.key === Qt.Key_Escape" in text or "onEscapePressed" in text:
        print(f"raw Escape handling remains in {relative}", file=sys.stderr)
        raise SystemExit(1)
print("ok - existing QML cancel paths use the shared key predicate")
PY
