#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_compositor "bar icon geometry test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping bar icon geometry test"
  exit 0
fi
require_command magick

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

ln -s "$ROOT/shell/Ui" "$test_tmp/Ui"
ln -s "$ROOT/shell/Commons" "$test_tmp/Commons"
# A white block with uneven transparent padding: 16x24 of ink inside 32x32.
magick -size 32x32 xc:none -fill white -draw 'rectangle 8,4 23,27' "$test_tmp/padded.png"
# Opaque to its edges: a dark dot a quarter of the tile wide. Nothing is
# transparent, so nothing may be trimmed and the dot must keep its proportion.
magick -size 32x32 xc:white -fill '#202020' -draw 'circle 16,16 16,12' "$test_tmp/opaque.png"

cat >"$test_tmp/shell.qml" <<'QML'
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui

ShellRoot {
  id: root

  readonly property string outDir: Quickshell.env("TEST_TMP")
  property int pendingGrabs: 0
  readonly property var icons: [
    bluetooth, network, audio, monitor, power, wideGlyph, widgetGlyph, mixed, vector, imageIcon,
    twoTone, slivered,
    verticalIcon, compactStatusIcon, compactVerticalStatusIcon, horizontalIndicator, verticalIndicator
  ]
  readonly property var iconNames: [
    "bluetooth", "network", "audio", "monitor", "power", "wideGlyph", "widgetGlyph", "mixed", "vector", "imageIcon",
    "twoTone", "slivered",
    "verticalIcon", "compactStatusIcon", "compactVerticalStatusIcon", "horizontalIndicator", "verticalIndicator"
  ]

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  function allVerified() {
    for (var i = 0; i < icons.length; i++) {
      if (!icons[i].inkVerified) return false
    }
    return paddedCrop.inkVerified && opaqueCrop.inkVerified
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
    // Whether the ink is centered, fills its canvas and stays inside it is the
    // shared rule table's job, and checkRules runs it over every icon below.
    // This used to re-implement the balance check here, which quietly drifted
    // stricter than the rule itself and failed icons the rule deliberately
    // exempts — a mark pinned by its own size cannot be moved to balance.
    if (icon.glyphPaintedWidth > icon.opticalWidth + 2 * IconRules.tolerance
        || icon.glyphPaintedHeight > icon.opticalHeight + 2 * IconRules.tolerance) {
      fail(name + " painted bounds overflow the optical canvas: " + icon.glyphPaintedWidth + "x" + icon.glyphPaintedHeight)
      return false
    }
    return true
  }

  function checkRules(item, name) {
    if (!item.inkVerified) {
      fail(name + " was never verified against the icon rules")
      return false
    }
    if (item.inkViolations.length > 0) {
      fail(name + " breaks icon rules " + item.inkViolations.join(",") + ": " + JSON.stringify(item.inkCompass))
      return false
    }
    return true
  }

  function checkSplit(text, icon, label, iconFirst) {
    var parts = Util.splitIconLabel(text)
    if (icon === null) {
      if (parts !== null) fail("'" + text + "' should not split into an icon")
      return parts === null
    }
    if (!parts || parts.icon !== icon || parts.label !== label || parts.iconFirst !== iconFirst) {
      fail("'" + text + "' split into " + JSON.stringify(parts))
      return false
    }
    return true
  }

  // Finds a named part inside a button's icon, to see what brightness the
  // flattening rule left it at.
  function partOpacity(item, name) {
    if (!item) return -1
    if (item.objectName === name) return item.opacity
    for (var i = 0; i < item.children.length; i++) {
      var found = partOpacity(item.children[i], name)
      if (found >= 0) return found
    }
    return -1
  }

  function checkTwoTone() {
    var keptSolid = partOpacity(twoTone, "solid")
    var keptFaded = partOpacity(twoTone, "faded")
    if (keptSolid !== 1 || Math.abs(keptFaded - 0.24) > 0.001) {
      fail("a two-tone logo was flattened: " + keptSolid + "," + keptFaded)
      return false
    }
    if (partOpacity(slivered, "sliver") !== 1) {
      fail("a faded sliver was left dim: " + partOpacity(slivered, "sliver"))
      return false
    }
    return true
  }

  function checkWeight() {
    // Two icons the same size on a ruler are not the same size to a reader.
    // A densely inked mark is fitted a little smaller than a sparse one, so
    // the row reads even rather than merely measuring even.
    if (IconRules.weightFit(IconRules.referenceCoverage) !== 1) {
      fail("a mark at the reference density was resized anyway")
      return false
    }
    var dense = IconRules.weightFit(0.75)
    var sparse = IconRules.weightFit(0.3)
    if (!(dense < 1) || !(sparse > 1)) {
      fail("density does not move the fit: dense=" + dense + " sparse=" + sparse)
      return false
    }
    if (!(dense < sparse)) {
      fail("a dense mark is not fitted smaller than a sparse one")
      return false
    }
    // Bounded at both ends, so no measurement can run away with the size.
    if (IconRules.weightFit(0.999) < IconRules.weightFitMin - 0.001
        || IconRules.weightFit(0.001) > IconRules.weightFitMax + 0.001) {
      fail("the density nudge is not bounded")
      return false
    }
    // Every lone icon keeps the same canvas as every other, so the open-panel
    // mark under one is the same length as under any other. It is wider than
    // the block along the bar, which is where a wide mark's long axis lands.
    if (Math.abs(vector.opticalWidth - wideGlyph.opticalWidth) > 0.001
        || Math.abs(vector.opticalHeight - wideGlyph.opticalHeight) > 0.001) {
      fail("icons do not share one canvas: " + vector.opticalWidth + "x" + vector.opticalHeight
        + " vs " + wideGlyph.opticalWidth + "x" + wideGlyph.opticalHeight)
      return false
    }
    // A wide mark comes out at the row's proportions rather than a fraction of
    // its height: fitting the long side alone is what made it read as broken.
    if (!(wideGlyph.glyphPaintedHeight > vector.glyphPaintedHeight * 0.6)) {
      fail("a wide glyph renders far shorter than a square one: "
        + wideGlyph.glyphPaintedHeight + " vs " + vector.glyphPaintedHeight)
      return false
    }
    return true
  }

  function checkRuleTable() {
    var same = function(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    if (!same(IconRules.evaluate(null), ["unmeasured"])) return fail("rules accept a missing measurement"), false
    if (!same(IconRules.evaluate({ n: 0.4, s: 0.6, e: 2.5, w: 2.5, nw: 3, ne: 3, se: 3, sw: 3, balanceX: 0, balanceY: 0.2 }), []))
      return fail("rules reject an icon that fills one axis and balances"), false
    // A mark far smaller than its block is short, however centered it is.
    if (!same(IconRules.evaluate({ n: 8, s: 8, e: 8, w: 8, balanceX: 0, balanceY: 0,
        block: 40, canvasWidth: 40, canvasHeight: 40 }), ["sized"]))
      return fail("rules miss an icon far short of its block"), false
    // And one fitted by the middle of its dimensions is not called short for
    // failing to touch an edge.
    if (!same(IconRules.evaluate({ n: 3, s: 3, e: 3, w: 3, balanceX: 0, balanceY: 0,
        block: 40, canvasWidth: 40, canvasHeight: 40 }), []))
      return fail("rules fault a mark fitted by the middle of its dimensions"), false
    // A box centered to the pixel still fails if the weight inside it is not:
    // that is the icon that reads high or low in an otherwise level row.
    // A mark pressed against one end has spent its room and is not faulted.
    if (!same(IconRules.evaluate({ n: 0, s: 0, e: 0, w: 4, balanceX: -2.2, balanceY: 0 }), []))
      return fail("rules fault a mark that has already spent its room"), false
    if (!same(IconRules.evaluate({ n: 0, s: 0, e: 2, w: 2, balanceX: -2.2, balanceY: 0 }), ["balanced"]))
      return fail("rules miss an icon whose weight sits off center"), false
    if (!same(IconRules.evaluate({ n: 0, s: 0, e: 2, w: 2.5, balanceX: 1.4, balanceY: 0 }), ["balanced"]))
      return fail("rules miss an off-center icon"), false
    // A mark reaching both ends of its canvas cannot be moved, so its weight
    // is not held against it.
    if (!same(IconRules.evaluate({ n: 0, s: 0, e: 0, w: 0, balanceX: 2.4, balanceY: 0 }), []))
      return fail("rules fault a pinned icon for weight it cannot move"), false
    // Across the bar, weight is never the question — filling the block is.
    if (!same(IconRules.evaluate({ n: 0, s: 0, e: 2, w: 2, balanceX: 0, balanceY: -2.2 }), []))
      return fail("rules fault an icon for where it weighs across the bar"), false
    if (IconRules.evaluate({ n: 0, s: 0, e: 0, w: 0, nw: -3, ne: 0, se: 0, sw: 0, balanceX: 0, balanceY: 0 }).indexOf("contained") === -1)
      return fail("rules miss ink spilling past a corner"), false
    // One measured pixel is the finest the rule can be held to, so a render
    // coarser than a logical pixel widens the allowance rather than failing
    // everything measured in it.
    if (!same(IconRules.evaluate({ n: 0, s: 1.004, e: 0, w: 0, balanceX: 0, balanceY: 0.5, pixel: 1.004 }), []))
      return fail("rules fail an icon by less than the pixel it was measured in"), false
    var compass = IconRules.compass({ rect: Qt.rect(0.25, 0, 0.5, 1), centroid: Qt.point(0.5, 0.75), width: 40, height: 40,
      diagonal: Qt.rect(0.2, 0.2, 0.6, 0.6), diagonalWidth: 56, diagonalHeight: 56 }, 16, 16)
    if (Math.abs(compass.n) > 0.001 || Math.abs(compass.s) > 0.001 || Math.abs(compass.w - 4) > 0.001 || Math.abs(compass.e - 4) > 0.001
        || Math.abs(compass.nw - 4.48) > 0.001 || Math.abs(compass.se - 4.48) > 0.001)
      return fail("compass margins are not scaled to the canvas: " + JSON.stringify(compass)), false
    if (Math.abs(compass.balanceX) > 0.001 || Math.abs(compass.balanceY - 4) > 0.001)
      return fail("compass does not report where the ink balances: " + JSON.stringify(compass)), false
    // Weight is brought onto the center only as far as the box has room, and
    // never on the axis the icon already fills.
    var shift = IconRules.balanceShift(Qt.rect(0.2, 0, 0.6, 1), Qt.point(0.65, 0.5), 0, "y")
    if (Math.abs(shift.x + 0.15) > 0.001 || Math.abs(shift.y) > 0.001)
      return fail("balance shift does not center the weight: " + JSON.stringify(shift)), false
    var pinned = IconRules.balanceShift(Qt.rect(0, 0, 1, 1), Qt.point(0.3, 0.7), 0, "y")
    if (Math.abs(pinned.x) > 0.001 || Math.abs(pinned.y) > 0.001)
      return fail("balance shift pushes an icon off the room it has: " + JSON.stringify(pinned)), false
    return true
  }

  // Captures an item and reports the canvas its icon should fill, as a
  // fraction of the item, so the pixels can be judged outside.
  function grab(item, name) {
    pendingGrabs++
    item.grabToImage(function(result) {
      if (!result || !result.saveToFile(root.outDir + "/" + name + ".png")) {
        root.fail(name + " could not be captured")
        return
      }
      console.log("GRAB " + name + " " + item.opticalSize + " " + item.width + " " + item.height)
      if (--root.pendingGrabs === 0) {
        console.log("RESULT pass")
        Qt.quit()
      }
    })
  }

  function runChecks() {
    if (!checkRuleTable()) return
    if (!checkTwoTone()) return
    if (!checkWeight()) return
    if (!checkSplit("󰂯", "󰂯", "", true)) return
    if (!checkSplit("󰄀 4", "󰄀", "4", true)) return
    if (!checkSplit("21% 󰁹", "󰁹", "21%", false)) return
    if (!checkSplit("5:40 PM", null)) return
    if (!checkSplit("en", null)) return
    if (!checkSplit("A󰁹", null)) return
    if (!checkIcon(bluetooth, "bluetooth")) return
    if (!checkIcon(network, "network")) return
    if (!checkIcon(audio, "audio")) return
    if (!checkIcon(monitor, "monitor")) return
    if (!checkIcon(power, "power")) return
    for (var i = 0; i < icons.length; i++) {
      if (!checkRules(icons[i], iconNames[i])) return
    }
    if (!checkRules(paddedCrop, "paddedCrop")) return
    if (!checkRules(opaqueCrop, "opaqueCrop")) return
    var normalizedScales = [bluetooth.glyphScale, network.glyphScale, audio.glyphScale,
      monitor.glyphScale, power.glyphScale]
    if (new Set(normalizedScales).size < 2) {
      fail("unlike glyphs were not sized independently")
      return
    }
    if (!widgetGlyph.hasIconGlyph || widgetGlyph.labelWidth !== 0) {
      fail("a plain WidgetButton holding one glyph is not treated as an icon")
      return
    }
    if (widgetGlyph.opticalSize !== Style.bar.iconCanvas || widgetGlyph.implicitWidth !== Style.bar.iconSlot) {
      fail("an icon-only WidgetButton does not take the shared canvas and slot: " + widgetGlyph.opticalSize + " in " + widgetGlyph.implicitWidth)
      return
    }
    if (Math.abs(widgetGlyph.paintedX + widgetGlyph.paintedWidth / 2 - widgetGlyph.width / 2) > IconRules.tolerance) {
      fail("painted bounds are not centered on the button: " + widgetGlyph.paintedX + "+" + widgetGlyph.paintedWidth)
      return
    }
    if (!mixed.hasIconGlyph || mixed.labelText !== "21%" || mixed.iconFirst || mixed.labelWidth <= 0) {
      fail("mixed label did not split into label and icon")
      return
    }
    if (mixed.contentWidth <= mixed.opticalSize + mixed.labelWidth) {
      fail("icon and label are not spaced apart")
      return
    }
    if (mixed.implicitWidth !== Style.bar.iconSlot * 2 || plainText.implicitWidth === Style.bar.iconSlot) {
      fail("labelled buttons do not keep their own width")
      return
    }
    if (Math.abs(mixed.paintedWidth - mixed.contentWidth) > 0.01) {
      fail("a labelled button's painted bounds do not span icon and label")
      return
    }
    if (plainDot.hasIconGlyph || plainDot.labelWidth <= 0 || plainDot.glyphFontSize !== 0 || plainDot.inkViolations.length !== 0) {
      fail("normalizeIcon: false did not keep the glyph as text")
      return
    }
    if (plainText.hasIconGlyph || plainText.labelWidth <= 0) {
      fail("plain text is treated as an icon")
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
    if (verticalIndicator.implicitWidth !== Style.bar.sizeVertical || verticalIndicator.implicitHeight >= Style.bar.iconSlot) {
      fail("vertical indicator does not retain compact spacing")
      return
    }
    if (verticalIndicator.glyphFontSize !== Style.font.caption) {
      fail("indicator does not retain its authored font size")
      return
    }
    var indicatorCanvas = Style.bar.iconCanvas * Style.font.caption / Style.bar.iconFont
    if (Math.abs(verticalIndicator.opticalSize - indicatorCanvas) > 0.01 || verticalIndicator.opticalSize >= Style.bar.iconCanvas) {
      fail("indicator canvas is not scaled down with its font: " + verticalIndicator.opticalSize)
      return
    }
    if (horizontalIndicator.implicitWidth >= Style.bar.iconSlot) {
      fail("horizontal indicator does not retain compact spacing")
      return
    }
    if (horizontalIndicatorPair.implicitWidth >= Style.bar.iconSlot * 2
        || verticalIndicatorPair.implicitHeight >= Style.bar.iconSlot * 2) {
      fail("indicator groups do not retain compact internal spacing")
      return
    }
    if (compactStatusIcon.implicitWidth !== Style.bar.statusSlot
        || compactVerticalStatusIcon.implicitHeight !== Style.bar.statusSlot) {
      fail("compact status icons do not use the shared status slot")
      return
    }

    root.grab(bluetooth, "bluetooth")
    root.grab(network, "network")
    root.grab(monitor, "monitor")
    root.grab(widgetGlyph, "widget-glyph")
    root.grab(vector, "vector")
    root.grab(imageIcon, "image-icon")
    root.grab(paddedCrop, "padded")
    root.grab(opaqueCrop, "opaque")
  }

  Timer {
    interval: 50
    running: true
    repeat: true
    property int attempts: 0

    onTriggered: {
      if (++attempts > 300) {
        var waiting = []
        for (var i = 0; i < root.icons.length; i++) if (!root.icons[i].inkVerified) waiting.push(root.iconNames[i])
        if (!paddedCrop.inkVerified) waiting.push("paddedCrop")
        if (!opaqueCrop.inkVerified) waiting.push("opaqueCrop")
        root.fail("ink verification did not finish for " + waiting.join(","))
        return
      }
      if (!root.allVerified()) return

      running = false
      root.runChecks()
    }
  }

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

  Window {
    width: 480
    height: 160
    visible: true
    color: "transparent"
    flags: Qt.FramelessWindowHint

    Row {
      BarIconButton { id: bluetooth; bar: testBar; text: "󰂯" }
      BarIconButton { id: network; bar: testBar; text: "󰖩" }
      BarIconButton { id: audio; bar: testBar; text: "󰖁" }
      BarIconButton { id: monitor; bar: testBar; text: "󰍹" }
      BarIconButton { id: power; bar: testBar; text: "󰁹" }
      BarIconButton { id: wideGlyph; bar: testBar; text: String.fromCodePoint(0xF08AE) }
      BarIconButton {
        id: vector
        bar: testBar
        iconComponent: Component { Item { Rectangle { anchors.centerIn: parent; width: 12; height: 12 } } }
      }
      // A logo genuinely drawn in two tones: half of it is the second tone,
      // so it is left as its author drew it.
      BarIconButton {
        id: twoTone
        bar: testBar
        iconComponent: Component {
          Item {
            Rectangle { objectName: "solid"; x: 0; y: 4; width: 8; height: 8; color: "white" }
            Rectangle { objectName: "faded"; x: 8; y: 4; width: 8; height: 8; color: "white"; opacity: 0.24 }
          }
        }
      }
      // The same fade over a sliver of the mark is an accident, and goes back
      // to full.
      BarIconButton {
        id: slivered
        bar: testBar
        iconComponent: Component {
          Item {
            Rectangle { objectName: "solid"; x: 0; y: 4; width: 15; height: 8; color: "white" }
            Rectangle { objectName: "sliver"; x: 15; y: 4; width: 1; height: 8; color: "white"; opacity: 0.24 }
          }
        }
      }
      BarIconButton {
        id: imageIcon
        bar: testBar
        iconComponent: Component {
          Image {
            source: "file://" + Quickshell.env("TEST_TMP") + "/padded.png"
            fillMode: Image.PreserveAspectFit
          }
        }
      }
      BarIconButton { id: compactStatusIcon; bar: testBar; text: ""; slotSize: Style.bar.statusSlot }
      Row {
        id: horizontalIndicatorPair
        BarIndicator { id: horizontalIndicator; bar: testBar; active: true; activeText: "󰅶" }
        BarIndicator { bar: testBar; active: true; activeText: "󰔎" }
      }
    }

    Row {
      y: 40
      // Third-party patterns: a plain WidgetButton with one glyph, a label
      // with a trailing icon, a text-sized glyph marker, and plain text.
      WidgetButton { id: widgetGlyph; bar: testBar; text: "󰑓" }
      BarIconButton { id: mixed; bar: testBar; text: "21% 󰁹"; slotSize: Style.bar.iconSlot * 2 }
      WidgetButton { id: plainDot; bar: testBar; text: "󱓻"; normalizeIcon: false }
      WidgetButton { id: plainText; bar: testBar; text: "5:40 PM" }
    }

    Column {
      y: 80
      BarIconButton { id: verticalIcon; bar: verticalBar; text: "" }
      BarIconButton { id: compactVerticalStatusIcon; bar: verticalBar; text: ""; slotSize: Style.bar.statusSlot }
      Column {
        id: verticalIndicatorPair
        BarIndicator { id: verticalIndicator; bar: verticalBar; active: true; activeText: "󰅶" }
        BarIndicator { bar: verticalBar; active: true; activeText: "󰔎" }
      }
    }

    Row {
      x: 300
      y: 80
      spacing: 8
      AutoCropImage { id: paddedCrop; width: 16; height: 16; source: "file://" + root.outDir + "/padded.png" }
      AutoCropImage { id: opaqueCrop; width: 16; height: 16; source: "file://" + root.outDir + "/opaque.png" }
    }
  }
}
QML

output=$(timeout 40 env \
  TEST_TMP="$test_tmp" \
  QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
  quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "bar icon geometry fixture exits cleanly"
}

if ! grep -q 'RESULT pass' <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "bar icons meet the shared icon rules"
fi

pass "bar icons meet the shared icon rules"

# Prints "W H w h x y": the captured size and the trim box of its alpha channel.
ink_geometry() {
  local geometry
  geometry=$(magick "$1" -alpha extract -format '%w %h %@' info: 2>/dev/null)
  [[ $geometry =~ ^([0-9]+)\ ([0-9]+)\ ([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]] ||
    fail "$2 has measurable painted pixels" "$geometry"
  echo "${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]} ${BASH_REMATCH[4]} ${BASH_REMATCH[5]} ${BASH_REMATCH[6]}"
}

# Every captured icon's ink must reach its optical canvas on the longest axis
# and sit on the item's center, judged on rendered pixels within one device
# pixel. The canvas is a fraction of the captured item, so scale it by the
# capture. Covers font glyphs, a plain WidgetButton glyph, and icon components
# drawn as a small rectangle and as a padded image.
while read -r _ name optical item_width _; do
  read -r width height ink_width ink_height ink_x ink_y < <(ink_geometry "$test_tmp/$name.png" "$name")
  case $name in
    padded|opaque) continue ;;
  esac
  awk -v w="$width" -v h="$height" -v iw="$ink_width" -v ih="$ink_height" -v ix="$ink_x" -v iy="$ink_y" \
    -v optical="$optical" -v item="$item_width" '
    function abs(v) { return v < 0 ? -v : v }
    BEGIN {
      target = w * optical / item
      extent = iw > ih ? iw : ih
      dx = (ix + iw / 2) - w / 2
      dy = (iy + ih / 2) - h / 2
      exit !(abs(extent - target) <= 1 && abs(dx) <= 1 && abs(dy) <= 1)
    }' || fail "$name pixels fill and center the optical canvas" "$width $height ${ink_width}x${ink_height}+${ink_x}+${ink_y} canvas=$optical item=$item_width"
done < <(grep '^GRAB ' <<<"$output" | sed 's/.*GRAB /GRAB /')
pass "icon pixels fill and center the optical canvas"

# The padded block's ink must now span the full height and sit centered, with
# the transparent margins gone.
read -r width height ink_width ink_height ink_x ink_y < <(ink_geometry "$test_tmp/padded.png" "auto-cropped image")
right_margin=$((width - ink_x - ink_width))
margin_delta=$((ink_x - right_margin))
(( margin_delta < 0 )) && margin_delta=$((-margin_delta))
(( ink_height == height && ink_y == 0 && ink_width < width && margin_delta <= 1 )) ||
  fail "auto-cropped pixels fill and center the available canvas" "$width $height ${ink_width}x${ink_height}+${ink_x}+${ink_y}"
pass "auto-cropped pixels fill and center the available canvas"

# An image opaque to its edges has nothing to trim: its dot must still be a
# quarter of the tile, not zoomed to fill it.
dot=$(magick "$test_tmp/opaque.png" -alpha off -colorspace gray -threshold 50% -negate -format '%w %@' info: 2>/dev/null)
[[ $dot =~ ^([0-9]+)\ ([0-9]+)x([0-9]+)\+ ]] || fail "opaque image keeps a measurable dot" "$dot"
tile_width=${BASH_REMATCH[1]}
dot_width=${BASH_REMATCH[2]}
(( dot_width * 4 >= tile_width - 4 && dot_width * 4 <= tile_width + 4 )) ||
  fail "opaque image is left untrimmed" "$dot"
pass "opaque image is left untrimmed"
