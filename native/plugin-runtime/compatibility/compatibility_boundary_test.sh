#!/bin/bash

set -euo pipefail

root=$1

if rg -n 'Hyprland|WlrLayershell|IpcHandler|DBus|Socket|XMLHttpRequest|execDetached|clipboard|screens|\.env\s*\(|shell/(Commons|Ui)' "$root/qml"; then
  echo "Quickshell compatibility module exposes ambient authority" >&2
  exit 1
fi

expected_core='LazyLoader Scope ShellRoot Singleton SystemClock'
actual_core=$(find "$root/qml/Quickshell" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' | sort | tr '\n' ' ' | sed 's/ $//')
[[ $actual_core == "$expected_core" ]]

expected_widgets='IconImage WrapperItem WrapperMouseArea WrapperRectangle'
actual_widgets=$(find "$root/qml/Quickshell/Widgets" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' | sort | tr '\n' ' ' | sed 's/ $//')
[[ $actual_widgets == "$expected_widgets" ]]

rg -Fq 'module Quickshell' "$root/qml/Quickshell/qmldir"
rg -Fq 'module Quickshell.Widgets' "$root/qml/Quickshell/Widgets/qmldir"
! rg -q '^(plugin|optional plugin|classname|linktarget|prefer)\b' "$root/qml/Quickshell/qmldir" "$root/qml/Quickshell/Widgets/qmldir"
