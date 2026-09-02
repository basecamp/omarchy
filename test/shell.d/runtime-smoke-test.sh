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

require_compositor "shell runtime smoke test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping shell runtime smoke test"
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

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
stub_bin="$TMPDIR/bin"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home" "$stub_bin"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

# Every plugin under ~/.config/omarchy/plugins hot-reloads, whoever wrote it.
hot_reload_id="acme.hot-reload"
hot_reload_dir="$test_home/.config/omarchy/plugins/$hot_reload_id"
mkdir -p "$hot_reload_dir"
cat >"$hot_reload_dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$hot_reload_id",
  "name": "Before Hot Reload",
  "version": "1.0.0",
  "kinds": ["overlay"],
  "entryPoints": {"overlay": "Overlay.qml"},
  "omarchy": {"clonedFrom": "omarchy.emojis"}
}
JSON
cat >"$hot_reload_dir/Overlay.qml" <<'QML'
import QtQuick

Item {
  function open(payloadJson) {}
  function close() {}
}
QML

# A keepLoaded service must keep its instance (and in-memory state) across a
# plugin rescan. The marker below can only survive if the object does.
keep_service_id="acme.keep-service"
keep_service_dir="$test_home/.config/omarchy/plugins/$keep_service_id"
mkdir -p "$keep_service_dir"
cat >"$keep_service_dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$keep_service_id",
  "name": "Keep Service",
  "version": "1.0.0",
  "kinds": ["service"],
  "keepLoaded": true,
  "entryPoints": {"service": "Service.qml"}
}
JSON
cat >"$keep_service_dir/Service.qml" <<'QML'
import QtQuick
import Quickshell.Io

Item {
  property string marker: ""

  IpcHandler {
    target: "acme-keep"

    function set(value: string): string {
      marker = value
      return "ok"
    }

    function get(): string {
      return marker
    }
  }
}
QML

cat >"$stub_bin/omarchy-update-available" <<'SH'
#!/bin/bash
echo "Omarchy update available (test)"
exit 0
SH
chmod +x "$stub_bin/omarchy-update-available"

cat >"$stub_bin/curl" <<'SH'
#!/bin/bash

case "${*: -1}" in
  *'?format=j1')
    printf '{"current_condition":[{"weatherCode":"113","temp_F":"72"}]}\n'
    ;;
  *'?format=%l')
    printf 'Test City, Test Region\n'
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/curl"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
PATH="$stub_bin:$ROOT/bin:$PATH" \
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

plugins=""
for _ in {1..80}; do
  plugins=$(shell_ipc shell listPlugins 2>/dev/null || true)
  if jq -e 'length > 0' <<<"$plugins" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before plugins were listed"
  fi
  sleep 0.1
done

jq -e '
  map(.id) as $ids |
  all(["omarchy.menu", "omarchy.notifications", "omarchy.clock", "omarchy.osd"][]; $ids | index(.)) and
  all(.[]; (.kinds | type == "array") and (.enabled | type == "boolean") and (.canDisable | type == "boolean") and (.firstParty | type == "boolean") and (.clonedFrom | type == "string")) and
  ([.[].name] == ([.[].name] | sort))
' <<<"$plugins" >/dev/null || {
  printf 'Plugins:\n%s\n' "$plugins" | jq . >&2
  fail_with_log "shell IPC lists plugin metadata"
}
pass "shell IPC lists plugin metadata"

jq '.name = "After Hot Reload"' "$hot_reload_dir/manifest.json" >"$hot_reload_dir/manifest.json.tmp"
mv "$hot_reload_dir/manifest.json.tmp" "$hot_reload_dir/manifest.json"

hot_reload_name=""
for _ in {1..80}; do
  hot_reload_name=$(shell_ipc shell listPlugins 2>/dev/null |
    jq -r --arg id "$hot_reload_id" '.[] | select(.id == $id) | .name' 2>/dev/null || true)
  [[ $hot_reload_name == "After Hot Reload" ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited while reloading a changed installed plugin"
  fi
  sleep 0.1
done
[[ $hot_reload_name == "After Hot Reload" ]] ||
  fail_with_log "installed plugin changes reload without an explicit rescan"
pass "installed plugin changes reload without an explicit rescan"

[[ $(shell_ipc shell setPluginEnabled "$hot_reload_id" true) == "ok" ]] ||
  fail_with_log "installed plugin could not be enabled"
[[ $(shell_ipc shell summon omarchy.emojis "{}") == "ok" ]] ||
  fail_with_log "calls to a cloned source id do not reach its enabled clone"
shell_ipc_quiet shell hide omarchy.emojis >/dev/null
shell_ipc_quiet shell setPluginEnabled "$hot_reload_id" false >/dev/null
pass "shell IPC routes built-in ids to enabled clones"

shell_config=$(shell_ipc shell listShellConfig)
jq -e '
  .version == 1 and
  (.bar.layout.left | type == "array") and
  (.bar.layout.center | type == "array") and
  (.bar.layout.right | type == "array")
' <<<"$shell_config" >/dev/null || {
  printf 'Shell config:\n%s\n' "$shell_config" | jq . >&2
  fail_with_log "shell IPC returns effective shell config"
}
pass "shell IPC returns effective shell config"

[[ $(shell_ipc shell summon omarchy.menu '{"menu":"apps"}') == "ok" ]] || fail_with_log "shell IPC summons menu apps overlay"
shell_ipc_quiet shell hide omarchy.menu >/dev/null
[[ $(shell_ipc shell summon missing.plugin "{}") == "unknown" ]] || fail_with_log "shell IPC rejects unknown plugin"
pass "shell IPC summon and hide contract works"

[[ $(shell_ipc notifications ping) == "ok" ]] || fail_with_log "notifications IPC responds"
[[ $(shell_ipc notifications setDnd false) == "off" ]] || fail_with_log "notifications IPC toggles DND"
[[ $(shell_ipc media ping) == "ok" ]] || fail_with_log "media IPC responds"
jq -e '.hasPlayer | type == "boolean"' <<<"$(shell_ipc media status)" >/dev/null || fail_with_log "media IPC returns status JSON"
jq -e '.enabled | type == "boolean"' <<<"$(shell_ipc idle status)" >/dev/null || fail_with_log "idle IPC returns status JSON"
jq -e '.locked | type == "boolean"' <<<"$(shell_ipc lock status)" >/dev/null || fail_with_log "lock IPC returns status JSON"
[[ $(shell_ipc shell setPluginEnabled "$keep_service_id" true) == "ok" ]] ||
  fail_with_log "keepLoaded fixture service could not be enabled"
keep_marker_set=""
for _ in {1..80}; do
  keep_marker_set=$(shell_ipc acme-keep set "survived" 2>/dev/null || true)
  [[ $keep_marker_set == "ok" ]] && break
  sleep 0.1
done
[[ $keep_marker_set == "ok" ]] || fail_with_log "keepLoaded fixture service IPC responds"
[[ $(shell_ipc image-selector ping) == "ok" ]] || fail_with_log "image selector IPC responds"
[[ $(shell_ipc osd ping) == "ok" ]] || fail_with_log "OSD IPC responds"
[[ $(shell_ipc osd show '{"message":"Runtime smoke","duration":0}') == "ok" ]] || fail_with_log "OSD IPC opens"
[[ $(shell_ipc osd close) == "ok" ]] || fail_with_log "OSD IPC closes"
pass "plugin IPC contracts respond"

shell_ipc_quiet shell rescanPlugins >/dev/null
selector_rows_b64=$(printf '%s\t%s' "$TMPDIR/selector.png" "$TMPDIR/selector.png" | base64 -w 0)
selector_selection_file=$(mktemp "$TMPDIR/selector-selection.XXXXXX")
selector_done_file=$(mktemp "$TMPDIR/selector-done.XXXXXX")
rm -f "$selector_done_file"
selector_open=""
for _ in {1..80}; do
  selector_open=$(shell_ipc image-selector open "" "$selector_rows_b64" "" "$selector_selection_file" "$selector_done_file" false false 2>/dev/null || true)
  if [[ $selector_open == "ok" ]]; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited during plugin rescan"
  fi
  sleep 0.1
done
[[ $selector_open == "ok" ]] || fail_with_log "image selector IPC survives plugin rescan"
shell_ipc_quiet image-selector cancel "$selector_done_file" >/dev/null
rm -f "$selector_selection_file" "$selector_done_file"
pass "image selector IPC survives plugin rescan"

lock_status_after=$(shell_ipc lock status)
jq -e '.locked | type == "boolean"' <<<"$lock_status_after" >/dev/null || fail_with_log "lock IPC survives plugin rescan"
lock_event_after=$(jq -r '.lastEvent // empty' <<<"$lock_status_after")
[[ $lock_event_after != lock-stranded* ]] ||
  fail_with_log "plugin rescan does not strand the session lock ($lock_event_after)"
# A recreated instance would answer with a fresh, empty marker.
[[ $(shell_ipc acme-keep get) == "survived" ]] ||
  fail_with_log "plugin rescan keeps the keepLoaded service instance mounted"
pass "keepLoaded service instance survives plugin rescan"

# Dropping the service entry point from the manifest must drop the kept
# instance instead of leaving a zombie behind.
jq 'del(.keepLoaded) | .kinds = ["overlay"] | .entryPoints = {"overlay": "Service.qml"}' \
  "$keep_service_dir/manifest.json" >"$keep_service_dir/manifest.json.tmp"
mv "$keep_service_dir/manifest.json.tmp" "$keep_service_dir/manifest.json"
keep_gone=""
for _ in {1..80}; do
  keep_gone=$(shell_ipc acme-keep get 2>/dev/null || true)
  [[ $keep_gone != "survived" ]] && break
  sleep 0.1
done
[[ $keep_gone != "survived" ]] ||
  fail_with_log "kept service is dropped when its plugin stops declaring a service"
pass "kept service is dropped when its plugin stops declaring a service"

shell_ipc_quiet omarchy.system-update refresh >/dev/null 2>&1 || true
sleep 0.8

default_ids=$(jq -c '(.bar.layout.left + .bar.layout.center + .bar.layout.right) | map(.id // .)' "$ROOT/config/omarchy/shell.json")
visible_default_ids='[
  "omarchy.menu",
  "omarchy.workspaces",
  "omarchy.clock",
  "omarchy.weather",
  "omarchy.system-update",
  "omarchy.network",
  "omarchy.audio",
  "omarchy.monitor"
]'

geometry=""
for _ in {1..80}; do
  geometry=$(shell_ipc shell debugBarGeometry 2>/dev/null || true)
  if jq -e --argjson expected "$default_ids" '
    . as $rows | all($expected[]; . as $id | any($rows[]; .id == $id))
  ' <<<"$geometry" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before default bar geometry settled"
  fi
  sleep 0.1
done

if [[ -z $geometry ]]; then
  fail_with_log "debug bar geometry returned output"
fi

jq -e --argjson expected "$default_ids" --argjson visibleExpected "$visible_default_ids" '
  . as $rows |
  all($expected[]; . as $id | any($rows[]; .id == $id)) and
  all($visibleExpected[]; . as $id | any($rows[]; .id == $id and .visible == true and .width > 0 and .height > 0))
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "default bar layout renders expected module slots"
}
pass "default bar layout renders expected module slots"

jq -e '
  map(select(.section == "center")) | map(.id) as $center |
  ($center | index("omarchy.weather")) != null and
  ($center | index("omarchy.system-update")) != null and
  ($center | index("omarchy.indicators")) != null and
  (($center | index("omarchy.weather")) < ($center | index("omarchy.system-update"))) and
  (($center | index("omarchy.system-update")) < ($center | index("omarchy.indicators")))
' <<<"$geometry" >/dev/null || {
  printf 'Geometry:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "runtime geometry keeps update before indicators"
}

pass "runtime geometry keeps update before indicators"

for panel_id in omarchy.audio omarchy.bluetooth omarchy.monitor omarchy.network omarchy.power; do
  shell_ipc "$panel_id" open >/dev/null || fail_with_log "direct panel IPC opens $panel_id"
  shell_ipc "$panel_id" close >/dev/null || fail_with_log "direct panel IPC closes $panel_id"
done
pass "direct panel IPC opens and closes default panels"

# Each widget registers its IPC handler once per bar, and the bar is
# instantiated once per screen, so Quickshell reports one collision per screen
# past the first. Anything beyond that is two instances on the same screen —
# the shape duplicate component loads produced, where a sync pass that ran
# while a widget's asynchronous load was still in flight started a second one.
# Checked before the reload below, which rebuilds widgets by design.
screens=$(hyprctl -j monitors 2>/dev/null | jq 'length' 2>/dev/null || true)
[[ $screens =~ ^[0-9]+$ ]] && (( screens > 0 )) || screens=1
# No matches is the good case, and pipefail would otherwise abort the run.
worst=$(grep -oE "another handler is registered for target [a-z.-]+" "$log" |
  sort | uniq -c | sort -rn | head -1 | awk '{print $1}' || true)
worst=${worst:-0}
if (( worst > screens - 1 )); then
  grep "another handler is registered for target" "$log" | sed 's/^/  /' | head -20 >&2
  fail_with_log "each widget registers its IPC handler once per screen (saw $worst for $screens screen(s))"
fi
pass "each widget registers its IPC handler once per screen"

HOME="$test_home" OMARCHY_PATH="$test_root" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-plugin-disable" omarchy.audio

for _ in {1..80}; do
  shell_config=$(shell_ipc shell listShellConfig 2>/dev/null || true)
  geometry=$(shell_ipc shell debugBarGeometry 2>/dev/null || true)
  if jq -e 'all(.bar.layout.right[]; (.id // .) != "omarchy.audio")' <<<"$shell_config" >/dev/null 2>&1 && \
     jq -e 'all(.[]; .id != "omarchy.audio")' <<<"$geometry" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before reloaded bar geometry settled"
  fi
  sleep 0.1
done

jq -e 'all(.bar.layout.right[]; (.id // .) != "omarchy.audio")' <<<"$shell_config" >/dev/null || {
  printf 'Shell config after reload:\n%s\n' "$shell_config" | jq . >&2
  fail_with_log "plugin disable reloads shell config"
}

jq -e 'all(.[]; .id != "omarchy.audio")' <<<"$geometry" >/dev/null || {
  printf 'Geometry after reload:\n' >&2
  jq . <<<"$geometry" >&2
  fail_with_log "runtime bar layout updates after shell config reload"
}

pass "bar remove reloads shell config and updates bar layout"

# 'bar put' is what migrations use to place a newly shipped widget, so it has
# to place one that is missing and leave one that is already there alone,
# however often it runs.
bar_put() {
  HOME="$test_home" OMARCHY_PATH="$test_root" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-bar" put "$@"
}

center_ids() {
  jq -c '[.bar.layout.center[] | .id // .]' <<<"$(shell_ipc shell listShellConfig)"
}

bar_put omarchy.keyboard-layout --after omarchy.clock >/dev/null
for _ in {1..80}; do
  [[ $(center_ids) == *omarchy.keyboard-layout* ]] && break
  kill -0 "$QS_PID" 2>/dev/null || fail_with_log "test shell exited while putting a bar widget"
  sleep 0.1
done

jq -e '
  [.bar.layout.center[] | .id // .] as $ids
  | ($ids | index("omarchy.clock")) as $clock
  | ($ids | index("omarchy.keyboard-layout")) as $widget
  | $clock != null and $widget == $clock + 1
' <<<"$(shell_ipc shell listShellConfig)" >/dev/null ||
  fail_with_log "bar put places a widget after the one it names ($(center_ids))"
pass "bar put places a widget after the one it names"

placed=$(center_ids)
bar_put omarchy.keyboard-layout --section right >/dev/null
sleep 0.5
[[ $(center_ids) == "$placed" ]] ||
  fail_with_log "bar put left a widget already on the bar alone (was $placed, now $(center_ids))"
jq -e 'all(.bar.layout.right[]; (.id // .) != "omarchy.keyboard-layout")' \
  <<<"$(shell_ipc shell listShellConfig)" >/dev/null ||
  fail_with_log "bar put added a second copy of a widget already on the bar"
pass "bar put leaves a widget already on the bar alone"
