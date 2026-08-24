#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# shell.qml reaches a bar two ways, and only one of them is covered elsewhere.
# manifest-entrypoints-test.sh instantiates the built-in bar directly, which
# exercises defaultBarComponent's declarative properties; nothing exercised
# pluginBarLoader. Both bugs this covers were invisible from the built-in path:
# the loader omitting the injected properties at creation (so a bar declaring
# them `required` could not be instantiated at all), and Loader.Error failing to
# select the fallback (so a broken bar left the session with no bar and no
# message).
#
# Both cases run the real shell rather than a stand-in, because the loader is
# part of shell.qml and a reimplementation in a fixture would only test itself.

TMPDIR=""
QS_PID=""
test_root=""

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q "$@"
}

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_compositor "plugin bar loader test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping plugin bar loader test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
mkdir -p "$test_root"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

# A bar plugin whose injected properties are `required`, exactly as the
# first-party bar declares them. QML refuses to instantiate a component with a
# required property unset, so this loads only if the loader supplies all three at
# creation -- and it reports the values back, so a property that arrives as
# undefined fails the test rather than passing quietly.
write_required_bar() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.required-bar",
  "name": "Required Bar",
  "version": "1.0.0",
  "kinds": ["bar"],
  "entryPoints": {"bar": "Bar.qml"}
}
JSON
  cat >"$dir/Bar.qml" <<'QML'
import QtQuick
import Quickshell

Item {
  id: root

  required property string omarchyPath
  required property var barWidgetRegistry
  required property var barConfig

  property var shell: null
  property var manifest: null

  readonly property string resultPath: Quickshell.env("OMARCHY_QML_TEST_RESULT")

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  Component.onCompleted: {
    var payload = JSON.stringify({
      ok: true,
      omarchyPath: String(root.omarchyPath || ""),
      hasRegistry: root.barWidgetRegistry !== null && root.barWidgetRegistry !== undefined,
      hasConfig: root.barConfig !== null && root.barConfig !== undefined
    })

    if (resultPath)
      Quickshell.execDetached(["bash", "-lc",
        "printf '%s' " + shellQuote(payload) + " > " + shellQuote(resultPath)])
  }
}
QML
}

# A bar plugin that cannot load, for the fallback path.
write_broken_bar() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.broken-bar",
  "name": "Broken Bar",
  "version": "1.0.0",
  "kinds": ["bar"],
  "entryPoints": {"bar": "Bar.qml"}
}
JSON
  cat >"$dir/Bar.qml" <<'QML'
import QtQuick

Item {
  ThisTypeDoesNotExist {}
}
QML
}

write_shell_json() {
  local home="$1" bar_id="$2"
  mkdir -p "$home/.config/omarchy"
  cat >"$home/.config/omarchy/shell.json" <<JSON
{
  "version": 1,
  "bar": {"id": "$bar_id", "layout": {"left": [], "center": [], "right": []}}
}
JSON
}

start_shell() {
  local home="$1" log="$2" result="${3:-}"
  OMARCHY_PATH="$test_root" \
  OMARCHY_QML_TEST_RESULT="$result" \
  HOME="$home" \
  XDG_CONFIG_HOME="$home/.config" \
  XDG_CACHE_HOME="$home/.cache" \
  XDG_STATE_HOME="$home/.local/state" \
  QML2_IMPORT_PATH="$test_root/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  QML_IMPORT_PATH="$test_root/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  PATH="$ROOT/bin:$PATH" \
    quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
  QS_PID=$!
}

stop_shell() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  QS_PID=""
}

# ---------------------------------------------------------------- required bar
home_ok="$TMPDIR/home-ok"
log_ok="$TMPDIR/required-bar.log"
result="$TMPDIR/result.json"
write_required_bar "$home_ok/.config/omarchy/plugins/acme.required-bar"
write_shell_json "$home_ok" "acme.required-bar"
start_shell "$home_ok" "$log_ok" "$result"

for _ in {1..150}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log_ok" >&2
    fail "shell exited before the plugin bar reported in"
  fi
  sleep 0.1
done

if [[ ! -s $result ]]; then
  sed -n '1,120p' "$log_ok" >&2
  fail "a bar plugin with required injected properties never loaded"
fi

if ! jq -e '.ok == true and .hasRegistry == true and .hasConfig == true and (.omarchyPath | length > 0)' "$result" >/dev/null; then
  jq . "$result" >&2
  fail "the plugin bar loaded but its injected properties were not supplied"
fi

pass "a bar plugin declaring its injected properties required is loaded with them supplied"
stop_shell

# ------------------------------------------------------------------ broken bar
home_broken="$TMPDIR/home-broken"
log_broken="$TMPDIR/broken-bar.log"
write_broken_bar "$home_broken/.config/omarchy/plugins/acme.broken-bar"
write_shell_json "$home_broken" "acme.broken-bar"
start_shell "$home_broken" "$log_broken"

# The Loader.Error handler prints its warning before assigning failedBarId, so
# the log says nothing about whether the fallback actually took. Ask the shell
# instead: once it has given up on the broken bar, activeBarId is the built-in
# one, and listPlugins reports that as the active bar option.
fallback_took='any(.[]; .id == "omarchy.bar" and .active == true)
  and any(.[]; .id == "acme.broken-bar" and .active == false)'

for _ in {1..150}; do
  shell_ipc_quiet shell ping >/dev/null 2>&1 && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log_broken" >&2
    fail "shell exited before its IPC became available"
  fi
  sleep 0.1
done

plugins=""
for _ in {1..150}; do
  plugins=$(shell_ipc shell listPlugins 2>/dev/null || true)
  if jq -e "$fallback_took" <<<"$plugins" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,120p' "$log_broken" >&2
    fail "shell exited before falling back to the built-in bar"
  fi
  sleep 0.1
done

if ! jq -e "$fallback_took" <<<"$plugins" >/dev/null 2>&1; then
  jq -e 'map(select(.kinds | index("bar")))' <<<"$plugins" >&2 || printf '%s\n' "$plugins" >&2
  sed -n '1,120p' "$log_broken" >&2
  fail "a bar plugin that cannot load did not fall back to the built-in bar"
fi

pass "a bar plugin that cannot load falls back to the built-in bar"
