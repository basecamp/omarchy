#!/bin/bash

set -euo pipefail
root=$1
for forbidden in Quickshell FileView Process IpcHandler ScriptAction runtime invoke DBus Socket XMLHttpRequest; do
  if rg -n "${forbidden}" "$root"; then
    echo "presentation module exposes forbidden authority: ${forbidden}" >&2
    exit 1
  fi
done
expected='BarIconButton Color CursorSurface KeyboardPanel Panel PanelHero PanelKeyCatcher PanelSectionHeader PanelSeparator PanelSlider Style ToggleSwitch'
actual=$(find "$root" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' | sort | tr '\n' ' ' | sed 's/ $//')
[[ $actual == "$expected" ]]
