#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

rules="$ROOT/default/hypr/apps/system.lua"
class_rule='class = "(sublime_text|DesktopEditors|org.gnome.Nautilus|soffice|soffice.bin|libreoffice.*)"'

grep -F "$class_rule" "$rules" >/dev/null ||
  fail "LibreOffice native file dialogs are covered by the floating dialog rule"

grep -A2 -F "$class_rule" "$rules" | grep -F 'tag = "+floating-window"' >/dev/null ||
  fail "LibreOffice native file dialogs receive the floating-window tag"

pass "LibreOffice native file dialogs use the standard floating dialog treatment"
