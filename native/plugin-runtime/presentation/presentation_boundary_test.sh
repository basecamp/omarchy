#!/bin/bash

set -euo pipefail

root=$1

if rg -n '^\s*import\s+(Quickshell|qs\.)|Hyprland|WlrLayershell|IpcHandler|DBus|Socket|XMLHttpRequest|execDetached|shell/(Commons|Ui)' "$root"; then
  echo "presentation module exposes trusted host or ambient authority" >&2
  exit 1
fi

for file in "$root"/*.qml; do
  name=${file##*/}
  if [[ $name != "BrokerProcess.qml" && $name != "PrivateStorage.qml" && $name != "PackagedText.qml" && $name != "Panel.qml" ]] && rg -n '\bruntime\b|\binvoke\b|readPackagedText' "$file"; then
    echo "presentation primitive reaches the broker outside an SDK adapter: $name" >&2
    exit 1
  fi
done

if rg -n '\bruntime\.' "$root/Panel.qml" | rg -v 'runtime\.(settings|requestSurfaceIntent)'; then
  echo "panel presentation adapter reaches an undeclared runtime API" >&2
  exit 1
fi

expected='BarWidget Border BorderSurface BrokerProcess Button Color ConfirmDialog CursorSurface Dropdown KeyboardPanel PackagedText Panel PanelActionButton PanelHero PanelKeyCatcher PanelSectionHeader PanelSeparator PanelSlider PrivateStorage StdioCollector Style TextField Toggle ToggleSwitch ToolTip Util WidgetButton'
actual=$(find "$root" -maxdepth 1 -name '*.qml' -printf '%f\n' | sed 's/\.qml$//' | sort | tr '\n' ' ' | sed 's/ $//')
[[ $actual == "$expected" ]]

rg -Fq 'module Omarchy.PluginPresentation' "$root/qmldir"
! rg -q '^module qs\.(Commons|Ui)$' "$root/qmldir"
