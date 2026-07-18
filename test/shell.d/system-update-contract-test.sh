#!/bin/bash

set -euo pipefail

# shellcheck source=test/shell.d/base-test.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

manifest="$ROOT/shell/plugins/system-update/manifest.json"
service="$ROOT/shell/plugins/system-update/Service.qml"
widget="$ROOT/shell/plugins/system-update/BarWidget.qml"
packages="$ROOT/shell/plugins/system-update/PackagesTab.qml"
themes="$ROOT/shell/plugins/system-update/ThemesTab.qml"

jq -e '
  .schemaVersion == 1 and
  .id == "omarchy.system-update" and
  .kinds == ["service", "bar-widget"] and
  .keepLoaded == true and
  .entryPoints.service == "Service.qml" and
  .entryPoints.barWidget == "BarWidget.qml"
' "$manifest" >/dev/null || fail "system update manifest preserves the service-backed plugin contract"
pass "system update manifest preserves the service-backed plugin contract"

[[ ! -e $ROOT/shell/plugins/bar/widgets/SystemUpdate.qml ]] || fail "legacy system update widget is removed"
[[ ! -e $ROOT/shell/plugins/bar/widgets/SystemUpdate.manifest.json ]] || fail "legacy system update manifest is removed"
pass "legacy system update artifacts are removed"

grep -F 'target: "omarchy.system-update"' "$service" >/dev/null || fail "system update service preserves its IPC target"
grep -F 'function refresh(): void' "$service" >/dev/null || fail "system update service preserves refresh IPC"
grep -F 'function clear(): void' "$service" >/dev/null || fail "system update service preserves clear IPC"
grep -F 'interval: 6 * 60 * 60 * 1000' "$service" >/dev/null || fail "system update service preserves six-hour checks"
grep -F 'firstPartyServiceFor("omarchy.system-update")' "$widget" >/dev/null || fail "system update widget consumes the singleton service"
grep -F 'readonly property bool opened: popupOpen' "$widget" >/dev/null || fail "system update widget exposes popup state to the bar host"
grep -F 'function open()' "$widget" >/dev/null || fail "system update widget exposes the bar-host open contract"
grep -F 'id: actionWatchdog' "$service" >/dev/null || fail "theme actions have a bounded watchdog"
grep -F 'root._actionTimedOut = true' "$service" >/dev/null || fail "theme action timeouts enter an explicit failure state"
grep -F 'root.hasMaterialSymbols ? "\uF569" : "\uf466"' "$widget" >/dev/null \
  || fail "system update widget preserves the V1 package icon with a stock-font fallback"
grep -F 'anchors.verticalCenter: updateIcon.verticalCenter' "$widget" >/dev/null \
  || fail "system update count uses the V1-style corner badge"
grep -F 'anchors.horizontalCenterOffset: Style.space(7)' "$widget" >/dev/null \
  || fail "system update badge remains offset from the icon center"
grep -F 'root.updateService.themeRefreshing ? "\uf021" : "\uf1fc"' "$themes" >/dev/null \
  || fail "themes empty state uses a glyph available in the stock bar font"
if grep -F '\uf53f' "$themes" >/dev/null; then
  fail "themes empty state must not use a glyph missing from the stock bar font"
fi
pass "system update state and IPC are owned by one service"

grep -F '["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]' "$service" >/dev/null \
  || fail "package apply launches the full Omarchy update flow"
if grep -REn '(^|[^A-Za-z])(pacman|paru|yay)([^A-Za-z]|$)' \
  --include='*.qml' --include='*.js' "$ROOT/shell/plugins/system-update" >/dev/null; then
  fail "system update QML must not invoke package managers"
fi
grep -F 'root.updateService.launchPackageUpdate()' "$packages" >/dev/null || fail "packages tab delegates apply to the update service"
pass "package apply remains owned by omarchy-update"
