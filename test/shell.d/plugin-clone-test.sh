#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home/.config/omarchy" "$TMPDIR/bin"
CALLS="$TMPDIR/calls"

cat >"$TMPDIR/bin/omarchy-shell" <<'SH'
#!/bin/bash
if [[ $* == *"listShellConfig"* ]]; then
  if [[ -n ${FAKE_SHELL_CONFIG:-} ]]; then
    printf '%s\n' "$FAKE_SHELL_CONFIG"
  else
    printf '{}\n'
  fi
elif [[ $* == *"listPlugins"* ]]; then
  if [[ ${FAKE_NO_DISCOVERY:-0} == 1 ]]; then
    printf '[]\n'
  else
    find "$HOME/.config/omarchy/plugins" -mindepth 2 -maxdepth 2 -name manifest.json -print0 |
      xargs -0 -r jq -s 'map({id: .id, enabled: true})'
  fi
fi
exit 0
SH

for command in omarchy-bar omarchy-bar-plugin; do
  cat >"$TMPDIR/bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
exec "$OMARCHY_TEST_ROOT/bin/${0##*/}" "$@"
SH
done

for command in omarchy-plugin-enable omarchy-plugin-disable omarchy-notification-send; do
  cat >"$TMPDIR/bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
SH
done
chmod +x "$TMPDIR/bin/"*

clone_plugin() {
  local default_config='{
    "bar": {
      "layout": {
        "left": [{"id": "omarchy.menu"}],
        "center": [{"id": "omarchy.clock", "format": "HH:mm"}],
        "right": []
      }
    }
  }'
  HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    FAKE_CALLS="$CALLS" OMARCHY_TEST_ROOT="$ROOT" \
    FAKE_SHELL_CONFIG="${FAKE_CLONE_CONFIG:-$default_config}" \
    omarchy-plugin-clone "$@"
}

clone_plugin omarchy.clock >/dev/null
clock="$TMPDIR/home/.config/omarchy/plugins/local.clock"

for file in manifest.json BarWidget.qml Panel.qml Model.js; do
  [[ -f $clock/$file ]] || fail "clock clone is missing $file"
done
pass "clone copies the complete plugin"

grep -q 'import "Model.js"' "$clock/BarWidget.qml" &&
  grep -q 'Qt.resolvedUrl("Panel.qml")' "$clock/BarWidget.qml" ||
  fail "clock clone does not preserve local dependencies"
pass "clone keeps plugin dependencies local"

rg -qF "omarchy.clock" "$clock" -g '*.qml' -g '*.js' ||
  fail "clock clone does not preserve the stable runtime id"
pass "clone preserves the built-in runtime IPC id"

jq -e '
  .id == "local.clock" and
  .name == "My Clock" and
  .barWidget.displayName == "My Clock" and
  .omarchy.clonedFrom == "omarchy.clock" and
  .kinds == ["bar-widget"] and
  .entryPoints.barWidget == "BarWidget.qml"
' "$clock/manifest.json" >/dev/null || fail "clock clone manifest is incorrect"
pass "clone updates identity without replacing the manifest"

grep -qx 'omarchy-bar-plugin replace omarchy.clock local.clock' "$CALLS" ||
  fail "clone does not replace an active bar widget"
grep -qx 'omarchy-notification-send -g 󰐱 Editing Cloned Plugin Original plugin has been replace by clone.' "$CALLS" ||
  fail "clone does not notify that the editable clone is active"
jq -e '
  any(.bar.layout.center[];
    .id == "local.clock" and
    .format == "dddd HH:mm" and
    .formatAlt == "d MMMM \u0027W\u0027ww yyyy")
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null ||
  fail "clone does not preserve the active widget's placement and settings"
pass "clone switches bar widgets in place and confirms the editable clone"

jq '.bar.layout.center += ["omarchy.keyboard-layout"]' \
  "$TMPDIR/home/.config/omarchy/shell.json" >"$TMPDIR/shell.json"
mv "$TMPDIR/shell.json" "$TMPDIR/home/.config/omarchy/shell.json"
FAKE_CLONE_CONFIG='{
  "bar": {
    "layout": {
      "left": [],
      "center": ["omarchy.keyboard-layout"],
      "right": []
    }
  }
}' clone_plugin omarchy.keyboard-layout >/dev/null
jq -e '
  any(.bar.layout.center[]; .id == "local.keyboard-layout")
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null ||
  fail "clone does not replace a string-form bar entry"
pass "clone replaces legacy string-form bar entries"

clone_plugin omarchy.menu >/dev/null
menu="$TMPDIR/home/.config/omarchy/plugins/local.menu"

for file in manifest.json Menu.qml MenuModel.js BarWidget.qml; do
  [[ -f $menu/$file ]] || fail "menu clone is missing $file"
done
jq -e '
  .id == "local.menu" and
  .kinds == ["menu", "bar-widget"] and
  .entryPoints.menu == "Menu.qml" and
  .entryPoints.barWidget == "BarWidget.qml"
' "$menu/manifest.json" >/dev/null || fail "menu clone loses plugin kinds"
grep -qx 'omarchy-plugin-disable omarchy.menu' "$CALLS" ||
  fail "clone leaves the built-in half of a multi-kind plugin enabled"
pass "clone preserves multi-kind plugins"

HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  FAKE_CALLS="$CALLS" OMARCHY_TEST_ROOT="$ROOT" \
  omarchy-plugin-remove local.menu --yes >/dev/null
grep -qx 'omarchy-bar-plugin replace local.menu omarchy.menu' "$CALLS" &&
  grep -qx 'omarchy-plugin-enable omarchy.menu' "$CALLS" ||
  fail "removing a clone does not restore its built-in source"
pass "removing a clone restores its built-in source"

clone_plugin omarchy.active-window >/dev/null
[[ -f $TMPDIR/home/.config/omarchy/plugins/local.active-window/ActiveWindow.qml ]] ||
  fail "flat bar plugin clone is incomplete"
pass "flat bar plugins clone from adjacent manifests"

grep -qx 'omarchy-bar-plugin add local.active-window' "$CALLS" ||
  fail "clone does not activate a bar widget whose source is absent"
jq -e '
  any(.bar.layout.left[]; .id == "local.active-window")
' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null ||
  fail "clone does not add the absent widget using its default placement"
pass "clone activates an absent bar widget"

clone_plugin omarchy.indicators >/dev/null
indicators="$TMPDIR/home/.config/omarchy/plugins/local.indicators"
for file in Indicators.qml indicators/Dnd.qml indicators/Reminder.qml; do
  [[ -f $indicators/$file ]] || fail "indicators clone is missing $file"
done
grep -q 'Qt.resolvedUrl("indicators/"' "$indicators/Indicators.qml" ||
  fail "indicators clone does not point at its copied components"
pass "flat bar plugins declare extra clone dependencies"

clone_plugin omarchy.tray >/dev/null
[[ -f $TMPDIR/home/.config/omarchy/plugins/local.tray/TrayModel.js ]] ||
  fail "tray clone is missing its model"
pass "flat bar plugins keep local script dependencies"

clone_plugin omarchy.bar >/dev/null
grep -qx 'omarchy-bar use local.bar' "$CALLS" ||
  fail "clone does not select a cloned bar"
jq -e '.bar.id == "local.bar"' "$TMPDIR/home/.config/omarchy/shell.json" >/dev/null ||
  fail "clone does not persist the cloned bar as active"
pass "clone switches full bars"

clone_plugin omarchy.background >/dev/null
grep -qx 'omarchy-plugin-enable local.background' "$CALLS" ||
  fail "clone does not enable an ordinary cloned plugin"
grep -qx 'omarchy-plugin-disable omarchy.background' "$CALLS" ||
  fail "clone does not disable the ordinary source plugin"
pass "clone switches ordinary plugins"

mkdir -p "$TMPDIR/home/.config/omarchy/plugins/acme.example"
cat >"$TMPDIR/home/.config/omarchy/plugins/acme.example/manifest.json" <<'JSON'
{"id":"acme.example","name":"Example","kinds":["bar-widget"],"entryPoints":{"barWidget":"Widget.qml"}}
JSON
if clone_plugin acme.example >/dev/null 2>&1; then
  fail "clone accepts a user plugin"
fi
pass "clone is limited to built-in plugins"

if clone_plugin omarchy.weather custom.weather >/dev/null 2>&1; then
  fail "clone accepts a custom id"
fi
[[ ! -e $TMPDIR/home/.config/omarchy/plugins/local.weather ]] ||
  fail "rejected custom id leaves a clone behind"
pass "clone derives the local id"

if clone_plugin omarchy.weather --replace >/dev/null 2>&1; then
  fail "clone still accepts bar layout actions"
fi
[[ ! -e $TMPDIR/home/.config/omarchy/plugins/local.weather ]] ||
  fail "rejected bar action leaves a clone behind"
pass "clone does not accept manual switch options"

if clone_plugin >/dev/null 2>&1; then
  fail "clone opens an interactive picker without a source id"
fi
pass "clone requires an explicit source id"

if FAKE_NO_DISCOVERY=1 clone_plugin omarchy.osd >/dev/null 2>&1; then
  fail "clone succeeds before the shell discovers it"
fi
[[ ! -e $TMPDIR/home/.config/omarchy/plugins/local.osd ]] ||
  fail "failed clone discovery leaves a partial clone behind"
pass "clone removes a partial clone when switching fails"
