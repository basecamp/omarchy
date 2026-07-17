#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping bar icon geometry test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

ln -s "$ROOT/shell/Ui" "$test_tmp/Ui"
ln -s "$ROOT/shell/Commons" "$test_tmp/Commons"

cat >"$test_tmp/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  function checkIcon(icon, name) {
    if (icon.implicitWidth !== Style.bar.iconSlot) {
      fail(name + " slot width is " + icon.implicitWidth)
      return false
    }
    if (icon.opticalSize !== Style.bar.iconCanvas) {
      fail(name + " optical canvas is " + icon.opticalSize)
      return false
    }
    if (Math.abs(icon.opticalCenterErrorX) > 0.5) {
      fail(name + " painted bounds are over half a pixel off center by " + icon.opticalCenterErrorX)
      return false
    }
    if (icon.glyphFontSize !== Style.bar.iconFont) {
      fail(name + " font size is " + icon.glyphFontSize)
      return false
    }
    return true
  }

  Component.onCompleted: Qt.callLater(function() {
    if (!checkIcon(bluetooth, "bluetooth")) return
    if (!checkIcon(network, "network")) return
    if (!checkIcon(audio, "audio")) return
    if (!checkIcon(monitor, "monitor")) return
    if (!checkIcon(power, "power")) return
    var baseline = bluetooth.glyphBaselineY
    if (network.glyphBaselineY !== baseline || audio.glyphBaselineY !== baseline
        || monitor.glyphBaselineY !== baseline || power.glyphBaselineY !== baseline) {
      fail("glyph baselines do not match")
      return
    }
    if (vector.implicitWidth !== Style.bar.iconSlot || vector.opticalSize !== Style.bar.iconCanvas) {
      fail("vector icon does not share glyph geometry")
      return
    }
    if (verticalIcon.implicitWidth !== Style.bar.sizeVertical || verticalIcon.implicitHeight !== Style.bar.iconSlot) {
      fail("vertical icon does not use the shared slot")
      return
    }
    if (verticalIndicator.implicitWidth !== Style.bar.sizeVertical || verticalIndicator.implicitHeight !== Style.bar.iconSlot) {
      fail("vertical indicator does not use the shared slot")
      return
    }
    if (Math.abs(verticalIndicator.opticalCenterErrorX) > 0.5) {
      fail("vertical indicator is not optically centered")
      return
    }
    console.log("RESULT pass")
    Qt.quit()
  })

  QtObject {
    id: testBar
    property bool vertical: false
    property int barSize: Style.bar.sizeHorizontal
    property string fontFamily: Style.font.family
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function hideTooltip(target) {}
    function showTooltip(target, text) {}
  }

  QtObject {
    id: verticalBar
    property bool vertical: true
    property int barSize: Style.bar.sizeVertical
    property string fontFamily: Style.font.family
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    function registerClickTarget(target) {}
    function unregisterClickTarget(target) {}
    function hideTooltip(target) {}
    function showTooltip(target, text) {}
  }

  BarIconButton { id: bluetooth; bar: testBar; text: "󰂯" }
  BarIconButton { id: network; bar: testBar; text: "󰖩" }
  BarIconButton { id: audio; bar: testBar; text: "󰖁" }
  BarIconButton { id: monitor; bar: testBar; text: "󰍹" }
  BarIconButton { id: power; bar: testBar; text: "󰁹" }
  BarIconButton {
    id: vector
    bar: testBar
    iconComponent: Component { Rectangle { width: 12; height: 12 } }
  }
  BarIconButton { id: verticalIcon; bar: verticalBar; text: "\uf021" }
  BarIndicator { id: verticalIndicator; bar: verticalBar; active: true; activeText: "󰅶" }
}
QML

output=$(timeout 15 env \
  QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "bar icon geometry fixture exits cleanly"
}

if ! grep -q 'RESULT pass' <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "bar icons share slot and baseline geometry"
fi

pass "bar icons share slot and baseline geometry"
