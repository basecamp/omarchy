#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs.readFileSync(path.join(root, 'shell/Commons/Style.qml'), 'utf8')
const match = source.match(/function effectiveGapsOut\(hyprlandValue, overrides\) \{[\s\S]*?\n  \}/)
assert(match, 'style exposes its effective outer-gap calculation for testing')

const style = {}
vm.createContext(style)
vm.runInContext(match[0], style)

assertEqual(style.effectiveGapsOut(10, {}), 5, 'shell outer gap defaults to half the Hyprland gap')
assertEqual(style.effectiveGapsOut(18, {}), 9, 'default shell outer gap tracks custom Hyprland gaps')
assertEqual(style.effectiveGapsOut(10, { 'screen-edge-margin': 10 }), 10, 'screen-edge margin can align shell surfaces with windows')
assertEqual(style.effectiveGapsOut(10, { 'screen-edge-margin': 0 }), 0, 'screen-edge margin accepts a flush layout')
assertEqual(style.effectiveGapsOut(10, { 'screen-edge-margin': '12' }), 12, 'screen-edge margin accepts numeric string values')
assertEqual(style.effectiveGapsOut(10, { 'screen-edge-margin': -1 }), 5, 'negative screen-edge margins fall back to the Hyprland gap')
assertEqual(style.effectiveGapsOut(10, { 'screen-edge-margin': 'invalid' }), 5, 'invalid screen-edge margins fall back to the Hyprland gap')
JS

require_compositor "style token runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping style token runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

ln -s "$ROOT/shell/Commons" "$test_tmp/Commons"

cat >"$test_tmp/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(function() {
    Style.applyGapsOutJson('{"css":"10 10 10 10"}')
    Style.applyShellValues({})
    if (Style.gapsOut !== 5) {
      fail("default gap is " + Style.gapsOut)
      return
    }

    Style.applyShellValues({ "spacing.screen-edge-margin": "10" })
    if (Style.gapsOut !== 10) {
      fail("configured gap is " + Style.gapsOut)
      return
    }

    Style.applyShellValues({})
    if (Style.gapsOut !== 5) {
      fail("restored gap is " + Style.gapsOut)
      return
    }

    console.log("RESULT pass")
    Qt.quit()
  })
}
QML

output=$(timeout 15 env \
  QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "style token runtime fixture exits cleanly"
}

if ! grep -q 'RESULT pass' <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "shell style applies and removes the screen-edge margin override"
fi

pass "shell style applies and removes the screen-edge margin override"
