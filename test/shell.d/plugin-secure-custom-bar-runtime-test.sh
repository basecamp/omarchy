#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_root=""
test_home=""
qs_pid=""

cleanup() {
  if [[ -n $qs_pid ]] && kill -0 "$qs_pid" 2>/dev/null; then
    kill "$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
  fi
  [[ -n $test_root ]] && rm -rf -- "${test_root%/omarchy}"
}
trap cleanup EXIT

require_compositor "secure custom bar runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping secure custom bar runtime test"
  exit 0
fi

require_command jq

workspace=$(mktemp -d)
test_root="$workspace/omarchy"
test_home="$workspace/home"
log="$workspace/quickshell.log"
mkdir -p "$test_root" "$test_home/.config/omarchy/plugins/test.incompatible-bar" \
  "$test_home/.config/omarchy/plugins/test.compatible-bar"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

for plugin_id in test.incompatible-bar test.compatible-bar; do
  cat >"$test_home/.config/omarchy/plugins/$plugin_id/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$plugin_id",
  "name": "$plugin_id",
  "version": "1.0.0",
  "kinds": ["bar"],
  "entryPoints": {"bar": "Bar.qml"}
}
JSON
done

cat >"$test_home/.config/omarchy/plugins/test.incompatible-bar/Bar.qml" <<'QML'
import QtQuick

Item {
  function debugBarGeometry() {
    return [{ id: "test.incompatible-bar", visible: true, itemVisible: true }]
  }
}
QML

cat >"$test_home/.config/omarchy/plugins/test.compatible-bar/Bar.qml" <<'QML'
import QtQuick

Item {
  property var securePluginHost: null

  function debugBarGeometry() {
    var injected = securePluginHost && securePluginHost.testIdentity === "secure-host-stub"
    return [{ id: injected ? "test.compatible-bar.injected" : "test.compatible-bar.missing-host",
              visible: true, itemVisible: true }]
  }
}
QML

cat >"$workspace/SecurePluginHost.qml" <<'QML'
import QtQuick

Item {
  property var shell: null
  property var barWidgetRegistry: null
  property string testIdentity: "secure-host-stub"
  property var barEntries: []
  property string barOwnerScreenName: ""
  visible: false
}
QML

shell_ipc() {
  HOME="$test_home" OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

stop_shell() {
  if [[ -n $qs_pid ]] && kill -0 "$qs_pid" 2>/dev/null; then
    kill "$qs_pid"
    wait "$qs_pid" 2>/dev/null || true
  fi
  qs_pid=""
}

launch_shell() {
  local secure=$1
  : >"$log"
  if [[ $secure == true ]]; then
    HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
      XDG_CACHE_HOME="$test_home/.cache" XDG_STATE_HOME="$test_home/.local/state" \
      OMARCHY_PATH="$test_root" OMARCHY_PLUGIN_V2_ENABLED=1 \
      OMARCHY_PLUGIN_V2_SHELL_ENTRY="$workspace/SecurePluginHost.qml" \
      quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
  else
    HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" \
      XDG_CACHE_HOME="$test_home/.cache" XDG_STATE_HOME="$test_home/.local/state" \
      OMARCHY_PATH="$test_root" quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
  fi
  qs_pid=$!
  for _ in {1..100}; do
    shell_ipc -q shell ping >/dev/null 2>&1 && return
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.1
  done
  sed -n '1,200p' "$log" >&2
  fail "secure custom bar test shell did not become ready"
}

select_bar() {
  jq --arg id "$1" '.bar.id = $id' "$ROOT/config/omarchy/shell.json" \
    >"$test_home/.config/omarchy/shell.json"
}

wait_for_geometry_id() {
  local expected=$1 geometry
  for _ in {1..100}; do
    geometry=$(shell_ipc shell debugBarGeometry 2>/dev/null || true)
    if jq -e --arg id "$expected" 'any(.[]; .id == $id)' <<<"$geometry" >/dev/null 2>&1; then
      printf '%s\n' "$geometry"
      return
    fi
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.1
  done
  sed -n '1,200p' "$log" >&2
  fail "bar geometry did not contain $expected"
}

wait_for_log() {
  local expected=$1
  for _ in {1..100}; do
    grep -F "$expected" "$log" >/dev/null && return
    kill -0 "$qs_pid" 2>/dev/null || break
    sleep 0.1
  done
  sed -n '1,200p' "$log" >&2
  fail "shell log did not contain: $expected"
}

select_bar test.incompatible-bar
launch_shell false
wait_for_geometry_id test.incompatible-bar >/dev/null
stop_shell
pass "trusted schema-v1 custom bar remains active when schema v2 is off"

config_before=$(sha256sum "$test_home/.config/omarchy/shell.json" | cut -d' ' -f1)
launch_shell true
fallback_message='bar option test.incompatible-bar does not support sandboxed schema-v2 plugins; using omarchy.bar for this session'
wait_for_log "$fallback_message"
wait_for_geometry_id omarchy.menu >/dev/null
config_after=$(sha256sum "$test_home/.config/omarchy/shell.json" | cut -d' ' -f1)
[[ $config_after == "$config_before" ]] || fail "secure fallback mutated shell.json"
stop_shell
pass "schema v2 falls back from an incompatible custom bar without config mutation"

select_bar test.compatible-bar
launch_shell true
wait_for_geometry_id test.compatible-bar.injected >/dev/null
stop_shell
pass "schema-v2-compatible custom bar remains active and receives the secure host"
