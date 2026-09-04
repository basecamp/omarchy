#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
  return 0
}
trap cleanup EXIT

require_compositor "bar inline settings test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping bar inline settings test"
  exit 0
fi

require_command jq

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q "$@"
}

fail_with_log() {
  local description="$1"
  sed -n '1,240p' "$log" >&2
  fail "$description"
}

probe_label() {
  shell_ipc acme.settings-probe label 2>/dev/null || true
}

# The probe answers over IPC, and its handler re-registers with the widget, so
# poll rather than reading once: right after a reload the target is briefly gone.
await_label() {
  local want="$1" seen=""
  local _
  for _ in {1..80}; do
    seen=$(probe_label)
    [[ $seen == "$want" ]] && return 0
    if ! kill -0 "$QS_PID" 2>/dev/null; then
      fail_with_log "test shell exited while waiting for label '$want'"
    fi
    sleep 0.1
  done
  printf 'probe reports: %s\n' "${seen:-<no answer>}" >&2
  return 1
}

await_config() {
  local id="$1" want="$2" seen=""
  local _
  for _ in {1..80}; do
    seen=$(shell_ipc shell listShellConfig 2>/dev/null |
      jq -r --arg id "$id" '.bar.layout.right[] | select((.id? // .) == $id) | .label // ""' 2>/dev/null || true)
    [[ $seen == "$want" ]] && return 0
    if ! kill -0 "$QS_PID" 2>/dev/null; then
      fail_with_log "test shell exited while waiting for config '$want'"
    fi
    sleep 0.1
  done
  printf 'effective config reports: %s\n' "${seen:-<nothing>}" >&2
  return 1
}

set_label() {
  local id="${2:-acme.settings-probe}"
  jq --arg label "$1" --arg id "$id" '
    .bar.layout.right = (.bar.layout.right | map(
      if (.id? // .) == $id then .label = $label else . end
    ))
  ' "$shell_json" >"$shell_json.tmp"
  mv "$shell_json.tmp" "$shell_json"
}

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

# The widget under test reports the inline setting it was handed. A plain Item
# is all a bar widget entry point has to be, and declaring `settings` writable
# is what lets the bar inject into it.
probe_dir="$test_home/.config/omarchy/plugins/acme.settings-probe"
mkdir -p "$probe_dir"
cat >"$probe_dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.settings-probe",
  "name": "Settings Probe",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": {"barWidget": "BarWidget.qml"},
  "barWidget": {"defaultSection": "right", "defaults": {"label": "UNSET"}}
}
JSON
cat >"$probe_dir/BarWidget.qml" <<'QML'
import QtQuick
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  implicitWidth: 1
  implicitHeight: 1

  IpcHandler {
    target: "acme.settings-probe"

    function label(): string {
      var value = root.settings ? root.settings.label : undefined
      return value === undefined || value === null ? "UNSET" : String(value)
    }
  }
}
QML

# A second plugin, never placed in the bar. Reloading it churns the widget
# registry, which re-creates every bar widget item -- including the probe's.
bystander_dir="$test_home/.config/omarchy/plugins/acme.settings-bystander"
mkdir -p "$bystander_dir"
cat >"$bystander_dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.settings-bystander",
  "name": "Bystander Before",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": {"barWidget": "BarWidget.qml"},
  "barWidget": {"defaultSection": "right", "defaults": {}}
}
JSON
cat >"$bystander_dir/BarWidget.qml" <<'QML'
import QtQuick

Item {
  property var settings: ({})

  implicitWidth: 1
  implicitHeight: 1
}
QML

shell_json="$test_home/.config/omarchy/shell.json"
mkdir -p "$(dirname "$shell_json")"
jq '.bar.layout.right += [{"id": "acme.settings-probe", "label": "ALPHA"}]' \
  "$ROOT/config/omarchy/shell.json" >"$shell_json"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if shell_ipc_quiet shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before IPC became available"
  fi
  sleep 0.1
done

await_label ALPHA || fail_with_log "bar widget renders the inline setting it was configured with"
pass "bar widget renders the inline setting it was configured with"

# Changing only an inline setting takes applySettingsDelta, which patches the
# running widgets in place instead of rebuilding the layout.
set_label BRAVO
await_label BRAVO || fail_with_log "an inline settings change reaches the running widget"
pass "an inline settings change reaches the running widget"

# Reloading an unrelated plugin re-creates every bar widget item. The setting
# must survive it: the slot has to hand the re-created widget the current
# settings, not the ones it captured when the layout was built.
jq '.name = "Bystander After"' "$bystander_dir/manifest.json" >"$bystander_dir/manifest.json.tmp"
mv "$bystander_dir/manifest.json.tmp" "$bystander_dir/manifest.json"

bystander_name=""
for _ in {1..80}; do
  bystander_name=$(shell_ipc shell listPlugins 2>/dev/null |
    jq -r '.[] | select(.id == "acme.settings-bystander") | .name' 2>/dev/null || true)
  [[ $bystander_name == "Bystander After" ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited while reloading the unrelated plugin"
  fi
  sleep 0.1
done
[[ $bystander_name == "Bystander After" ]] ||
  fail_with_log "the unrelated plugin never reloaded, so nothing re-created the widget"

await_label BRAVO ||
  fail_with_log "an inline settings change survives an unrelated plugin reload"
pass "an inline settings change survives an unrelated plugin reload"

# A slot whose widget is not registered renders emptyModuleComponent, an Item
# with no `settings` property -- the same state every slot passes through while
# a plugin reloads. applySettingsDelta skips a slot in that state, so a write
# landing then reached nothing at all, and the widget came up with the value the
# layout was built with rather than the one in shell.json. Placing an entry
# whose plugin is not installed yet reproduces that without racing a reload.
jq '.bar.layout.right += [{"id": "acme.settings-late", "label": "ALPHA"}]' \
  "$shell_json" >"$shell_json.tmp"
mv "$shell_json.tmp" "$shell_json"
await_config acme.settings-late ALPHA ||
  fail_with_log "the shell never picked up the unregistered widget's entry"

set_label BRAVO acme.settings-late
await_config acme.settings-late BRAVO ||
  fail_with_log "the shell never picked up the change to the unregistered widget"

late_dir="$test_home/.config/omarchy/plugins/acme.settings-late"
mkdir -p "$late_dir"
cat >"$late_dir/BarWidget.qml" <<'QML'
import QtQuick
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  implicitWidth: 1
  implicitHeight: 1

  IpcHandler {
    target: "acme.settings-late"

    function label(): string {
      var value = root.settings ? root.settings.label : undefined
      return value === undefined || value === null ? "UNSET" : String(value)
    }
  }
}
QML
cat >"$late_dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.settings-late",
  "name": "Settings Late",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": {"barWidget": "BarWidget.qml"},
  "barWidget": {"defaultSection": "right", "defaults": {"label": "UNSET"}}
}
JSON

late_label=""
for _ in {1..80}; do
  late_label=$(shell_ipc acme.settings-late label 2>/dev/null || true)
  [[ $late_label == "BRAVO" ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited while the late widget registered"
  fi
  sleep 0.1
done
[[ $late_label == "BRAVO" ]] || {
  printf 'late widget reports: %s\n' "${late_label:-<no answer>}" >&2
  fail_with_log "a settings change made while the slot had no widget reaches it once it registers"
}
pass "a settings change made while the slot had no widget reaches it once it registers"
