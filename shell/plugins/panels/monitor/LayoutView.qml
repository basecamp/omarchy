import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  required property var bar
  signal backRequested()
  signal applied()

  readonly property var scaleChoices: [0.75, 1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3]
  readonly property var rotationLabels: ["Landscape", "90°", "Upside down", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]

  property var displays: []
  property int selectedIndex: -1
  property bool loading: false
  property bool applying: false
  property string errorText: ""
  property string statusText: "Drag displays to arrange them"
  property real layoutMinX: 0
  property real layoutMinY: 0
  property real canvasScale: 0.1
  property real canvasOffsetX: 0
  property real canvasOffsetY: 0

  implicitHeight: content.implicitHeight

  onSelectedIndexChanged: Qt.callLater(function() {
    displayModeDropdown.sync()
    mirrorTargetDropdown.sync()
    resolutionDropdown.sync()
    refreshDropdown.sync()
    scaleDropdown.sync()
    rotationDropdown.sync()
  })

  function cloneDisplay(display) {
    var result = {}
    for (var key in display) result[key] = display[key]
    return result
  }

  function selectedDisplay() {
    return selectedIndex >= 0 && selectedIndex < displays.length ? displays[selectedIndex] : null
  }

  function displayForName(name) {
    for (var i = 0; i < displays.length; i++)
      if (String(displays[i].name) === String(name)) return displays[i]
    return null
  }

  function displayPosition(display) {
    if (display && display.mirror) {
      var source = displayForName(display.mirror)
      if (source) return { x: Number(source.x), y: Number(source.y) }
    }
    return { x: Number(display.x), y: Number(display.y) }
  }

  function setDisplay(index, values) {
    if (index < 0 || index >= displays.length) return
    var next = displays.slice()
    var changed = cloneDisplay(next[index])
    for (var key in values) changed[key] = values[key]
    next[index] = changed
    displays = next
    if (!changed.mirror && extendedDisplayCount() > 1) {
      var position = Model.nearestValidPosition(displays, index, Number(changed.x), Number(changed.y))
      changed.x = position.x
      changed.y = position.y
      next[index] = changed
      displays = next.slice()
    }
    statusText = "Layout changed — apply when ready"
  }

  function extendedDisplayCount() {
    var count = 0
    for (var i = 0; i < displays.length; i++) if (!displays[i].mirror) count++
    return count
  }

  function updateLayoutBounds() {
    if (!displays.length || layoutCanvas.width <= 0) return
    var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (display.mirror) continue
      var size = Model.logicalSize(display)
      minX = Math.min(minX, Number(display.x))
      minY = Math.min(minY, Number(display.y))
      maxX = Math.max(maxX, Number(display.x) + size[0])
      maxY = Math.max(maxY, Number(display.y) + size[1])
    }
    if (!isFinite(minX)) return
    layoutMinX = minX
    layoutMinY = minY
    var padding = Style.space(72)
    canvasScale = Math.min(0.16,
      Math.max(1, layoutCanvas.width - padding) / Math.max(1, maxX - minX),
      Math.max(1, layoutCanvas.height - padding) / Math.max(1, maxY - minY)
    )
    canvasOffsetX = (layoutCanvas.width - (maxX - minX) * canvasScale) / 2
    canvasOffsetY = (layoutCanvas.height - (maxY - minY) * canvasScale) / 2
  }

  function displayX(display) { return canvasOffsetX + (displayPosition(display).x - layoutMinX) * canvasScale }
  function displayY(display) { return canvasOffsetY + (displayPosition(display).y - layoutMinY) * canvasScale }

  function commitDrag(index, itemX, itemY) {
    var desiredX = layoutMinX + (itemX - canvasOffsetX) / canvasScale
    var desiredY = layoutMinY + (itemY - canvasOffsetY) / canvasScale
    var position = Model.nearestValidPosition(displays, index, Math.round(desiredX / 20) * 20, Math.round(desiredY / 20) * 20)
    setDisplay(index, position)
  }

  function resolutionOf(mode) {
    var match = String(mode || "").match(/^(\d+x\d+)@/)
    return match ? match[1] : "preferred"
  }

  function refreshOf(mode) {
    var match = String(mode || "").match(/@(\d+(?:\.\d+)?)/)
    return match ? match[1] : ""
  }

  function resolutionOptions(display) {
    var options = [], seen = {}, modes = display && display.modes ? display.modes : []
    for (var i = 0; i < modes.length; i++) {
      var value = resolutionOf(modes[i])
      if (seen[value]) continue
      seen[value] = true
      options.push({ value: value, label: value.replace("x", " × ") })
    }
    return options
  }

  function refreshOptions(display) {
    var options = [], seen = {}, modes = display && display.modes ? display.modes : []
    var resolution = display ? resolutionOf(display.mode) : ""
    for (var i = 0; i < modes.length; i++) {
      var mode = String(modes[i]).replace("Hz", "")
      if (resolutionOf(mode) !== resolution) continue
      var value = refreshOf(mode)
      if (!value || seen[value]) continue
      seen[value] = true
      options.push({ value: value, label: value + " Hz" })
    }
    return options
  }

  function modeForResolution(display, resolution) {
    var modes = display && display.modes ? display.modes : []
    var preferredRate = Number(refreshOf(display ? display.mode : ""))
    var best = "", bestDistance = Infinity
    for (var i = 0; i < modes.length; i++) {
      var mode = String(modes[i]).replace("Hz", "")
      if (resolutionOf(mode) !== resolution) continue
      var distance = Math.abs(Number(refreshOf(mode)) - preferredRate)
      if (distance < bestDistance) { best = mode; bestDistance = distance }
    }
    return best
  }

  function scaleOptions() {
    var options = []
    for (var i = 0; i < scaleChoices.length; i++)
      options.push({ value: String(scaleChoices[i]), label: Math.round(Number(scaleChoices[i]) * 100) + "%" })
    return options
  }

  function rotationOptions() {
    var options = []
    for (var i = 0; i < rotationLabels.length; i++) options.push({ value: String(i), label: rotationLabels[i] })
    return options
  }

  function mirrorSourceOptions(display) {
    var options = []
    for (var i = 0; i < displays.length; i++) {
      var candidate = displays[i]
      if (!display || candidate.name === display.name || candidate.mirror) continue
      options.push({ value: String(candidate.name), label: String(candidate.name) })
    }
    return options
  }

  function displayModeOptions(display) {
    var options = [{ value: "extend", label: "Extend desktop" }]
    if ((display && display.mirror) || mirrorSourceOptions(display).length > 0)
      options.push({ value: "mirror", label: "Mirror display" })
    return options
  }

  function parseResult(raw) {
    try { return JSON.parse(String(raw || "{}").trim() || "{}") }
    catch (error) { return { ok: false, error: "The display service returned invalid data" } }
  }

  function refresh() {
    if (stateProc.running) return
    loading = true
    errorText = ""
    stateProc.running = true
  }

  function applyLayout() {
    if (applying || !displays.length) return
    var payload = []
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      payload.push({
        name: display.name,
        mode: display.mode,
        x: Math.round(display.x),
        y: Math.round(display.y),
        scale: Number(display.scale),
        transform: Number(display.transform),
        mirror: String(display.mirror || "")
      })
    }
    applying = true
    errorText = ""
    applyProc.command = ["omarchy-monitor-layout", "apply", JSON.stringify(payload)]
    applyProc.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: stateProc
    command: ["omarchy-monitor-layout", "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.error) { root.errorText = result.error; return }
        root.displays = result.monitors || []
        root.selectedIndex = 0
        for (var i = 0; i < root.displays.length; i++) if (root.displays[i].focused) root.selectedIndex = i
        root.statusText = root.displays.length + (root.displays.length === 1 ? " display connected" : " displays connected")
        Qt.callLater(root.updateLayoutBounds)
      }
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.errorText === "") root.errorText = "Could not read the current display layout"
    }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parseResult(text)
        if (result.error) root.errorText = result.error
      }
    }
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.statusText = "Layout saved"
        root.applied()
        root.refresh()
      } else if (root.errorText === "") root.errorText = "The layout could not be applied"
    }
  }

  Column {
    id: content
    width: parent.width
    spacing: Style.space(14)

    Item {
      width: parent.width
      implicitHeight: Math.max(backButton.height, headerLabels.implicitHeight, refreshButton.height)

      Rectangle {
        id: backButton
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: width
        radius: width / 2
        color: backHover.hovered
          ? Style.hoverFillFor(root.bar.foreground, Color.accent)
          : "transparent"

        Image {
          id: backImage
          anchors.centerIn: parent
          width: Style.space(17)
          height: width
          source: "back.svg"
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          visible: false
        }

        MultiEffect {
          anchors.fill: backImage
          source: backImage
          colorization: 1
          colorizationColor: root.bar.foreground
        }

        HoverHandler { id: backHover }
        TapHandler { onTapped: root.backRequested() }

        ToolTip {
          visible: backHover.hovered
          text: "Back"
          delay: 350
        }
      }

      Column {
        id: headerLabels
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Advanced"; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
        Text { anchors.horizontalCenter: parent.horizontalCenter; textFormat: Text.PlainText; text: root.statusText; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      }

      Rectangle {
        id: refreshButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: width
        radius: width / 2
        color: refreshHover.hovered
          ? Style.hoverFillFor(root.bar.foreground, Color.accent)
          : "transparent"
        border.width: refreshFocus.activeFocus ? Math.max(1, Style.focusBorderWidth) : 0
        border.color: Style.focusBorderFor(root.bar.foreground, Color.accent)
        opacity: root.loading ? 0.55 : 1

        Image {
          id: refreshImage
          anchors.centerIn: parent
          width: Style.space(17)
          height: width
          source: "refresh.svg"
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          visible: false
        }

        MultiEffect {
          anchors.fill: refreshImage
          source: refreshImage
          colorization: 1
          colorizationColor: root.bar.foreground
        }

        HoverHandler { id: refreshHover }
        TapHandler {
          enabled: !root.loading && !root.applying
          onTapped: root.refresh()
        }
        FocusScope {
          id: refreshFocus
          anchors.fill: parent
        }

        ToolTip {
          visible: refreshHover.hovered
          text: root.loading ? "Refreshing displays…" : "Refresh displays"
          delay: 350
        }
      }
    }

    Rectangle {
      id: layoutCanvas
      width: parent.width
      height: Style.space(230)
      radius: Math.max(6, Style.cornerRadius)
      color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.045)
      border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.13)
      clip: true
      onWidthChanged: root.updateLayoutBounds()
      onHeightChanged: root.updateLayoutBounds()

      Text {
        visible: !root.loading && root.displays.length === 0
        anchors.centerIn: parent
        text: "No active displays found"
        color: Qt.darker(root.bar.foreground, 1.4)
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: root.displays

        Rectangle {
          id: screenCard
          required property var modelData
          required property int index
          x: root.displayX(modelData)
          y: root.displayY(modelData)
          width: Math.max(72, Model.logicalSize(modelData)[0] * root.canvasScale)
          height: Math.max(48, Model.logicalSize(modelData)[1] * root.canvasScale)
          z: modelData.mirror ? 2 : 1
          opacity: modelData.mirror ? 0.82 : 1
          radius: Math.max(4, Style.cornerRadius * 0.7)
          color: index === root.selectedIndex
            ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
            : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.09)
          border.width: index === root.selectedIndex ? 2 : 1
          border.color: index === root.selectedIndex ? Color.accent : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.3)

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(12)
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; textFormat: Text.PlainText; text: screenCard.modelData.name; color: root.bar.foreground; font.family: root.bar.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: screenCard.modelData.mirror ? "Mirrors " + screenCard.modelData.mirror : Model.modeDimensions(screenCard.modelData.mode).join(" × ") + "  ·  " + Math.round(Number(screenCard.modelData.scale) * 100) + "%"
              color: Qt.darker(root.bar.foreground, 1.35)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: screenCard.modelData.mirror ? Qt.PointingHandCursor : (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            drag.target: screenCard.modelData.mirror ? null : screenCard
            onPressed: root.selectedIndex = screenCard.index
            onReleased: if (!screenCard.modelData.mirror) root.commitDrag(screenCard.index, screenCard.x, screenCard.y)
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.errorText !== ""
      textFormat: Text.PlainText
      text: root.errorText
      color: root.bar.urgent
      wrapMode: Text.Wrap
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelSeparator { foreground: root.bar.foreground }

    Column {
      width: parent.width
      spacing: Style.space(10)
      visible: root.selectedDisplay() !== null

      RowLayout {
        width: parent.width
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.selectedDisplay() ? root.selectedDisplay().description : ""
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            textFormat: Text.PlainText
            text: root.selectedDisplay() && root.selectedDisplay().mirror
              ? root.selectedDisplay().name + " · mirrors " + root.selectedDisplay().mirror
              : root.selectedDisplay() ? root.selectedDisplay().name + " · " + Math.round(root.selectedDisplay().x) + ", " + Math.round(root.selectedDisplay().y) : ""
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      GridLayout {
        width: parent.width
        columns: 2
        columnSpacing: Style.space(12)
        rowSpacing: Style.space(10)

        ColumnLayout {
          Layout.fillWidth: true
          visible: root.displays.length > 1
          spacing: Style.space(5)

          SettingLabel { text: "DISPLAY MODE" }

          Dropdown {
            id: displayModeDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.displayModeOptions(root.selectedDisplay())
            Component.onCompleted: sync()
            onOptionsChanged: sync()
            function sync() { var display = root.selectedDisplay(); if (display) value = display.mirror ? "mirror" : "extend" }
            onChanged: function(nextValue) {
              var display = root.selectedDisplay()
              if (!display) return
              if (nextValue === "extend") root.setDisplay(root.selectedIndex, { mirror: "" })
              else { var sources = root.mirrorSourceOptions(display); if (sources.length) root.setDisplay(root.selectedIndex, { mirror: sources[0].value }) }
              Qt.callLater(mirrorTargetDropdown.sync)
            }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(5)

          SettingLabel { text: "RESOLUTION" }

          Dropdown {
            id: resolutionDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.resolutionOptions(root.selectedDisplay())
            Component.onCompleted: sync()
            onOptionsChanged: sync()
            function sync() { var display = root.selectedDisplay(); if (display) value = root.resolutionOf(display.mode) }
            onChanged: function(nextValue) { var mode = root.modeForResolution(root.selectedDisplay(), nextValue); if (mode) root.setDisplay(root.selectedIndex, { mode: mode }); Qt.callLater(refreshDropdown.sync) }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(5)

          SettingLabel { text: "REFRESH RATE" }

          Dropdown {
            id: refreshDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.refreshOptions(root.selectedDisplay())
            Component.onCompleted: sync()
            onOptionsChanged: sync()
            function sync() { var display = root.selectedDisplay(); if (display) value = root.refreshOf(display.mode) }
            onChanged: function(nextValue) { var display = root.selectedDisplay(); if (display) root.setDisplay(root.selectedIndex, { mode: root.resolutionOf(display.mode) + "@" + nextValue }) }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(5)

          SettingLabel { text: "SCALE" }

          Dropdown {
            id: scaleDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.scaleOptions()
            Component.onCompleted: sync()
            function sync() { var display = root.selectedDisplay(); if (display) value = String(display.scale) }
            onChanged: function(nextValue) { root.setDisplay(root.selectedIndex, { scale: Number(nextValue) }) }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(5)

          SettingLabel { text: "ORIENTATION" }

          Dropdown {
            id: rotationDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.rotationOptions()
            Component.onCompleted: sync()
            function sync() { var display = root.selectedDisplay(); if (display) value = String(Math.max(0, Math.min(7, Number(display.transform)))) }
            onChanged: function(nextValue) { root.setDisplay(root.selectedIndex, { transform: Number(nextValue) }) }
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          visible: root.selectedDisplay() && root.selectedDisplay().mirror
          spacing: Style.space(5)

          SettingLabel { text: "MIRROR SOURCE" }

          Dropdown {
            id: mirrorTargetDropdown
            Layout.fillWidth: true
            showLabel: false; foreground: root.bar.foreground; background: Color.popups.background; popupBorder: Color.popups.border; accent: Color.accent; fontFamily: root.bar.fontFamily
            options: root.mirrorSourceOptions(root.selectedDisplay())
            Component.onCompleted: sync()
            onOptionsChanged: sync()
            function sync() { var display = root.selectedDisplay(); if (display && display.mirror) value = String(display.mirror) }
            onChanged: function(nextValue) { root.setDisplay(root.selectedIndex, { mirror: String(nextValue) }) }
          }
        }
      }
    }

    PanelSeparator { foreground: root.bar.foreground }

    RowLayout {
      width: parent.width
      Text { Layout.fillWidth: true; text: "Saved in ~/.config/hypr/monitors.lua"; color: Qt.darker(root.bar.foreground, 1.4); font.family: root.bar.fontFamily; font.pixelSize: Style.font.caption }
      Button {
        text: root.applying ? "Applying…" : "Apply layout"
        bordered: true
        active: true
        enabled: !root.applying && !root.loading && root.displays.length > 0
        onClicked: root.applyLayout()
      }
    }
  }

  component SettingLabel: Text {
    textFormat: Text.PlainText
    color: Qt.darker(root.bar.foreground, 1.4)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0.8
  }
}
