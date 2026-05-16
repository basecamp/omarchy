import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "controlCenter"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  function run(command) {
    if (root.bar) root.bar.run(command)
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Volume controls live in the audioPanel bar widget, so the quick-settings
  // popup just hosts brightness + toggles.
  property int currentBrightness: -1
  property int pendingBrightness: -1

  // DND state is bound straight to the notifications service so toggling
  // from the quick-settings tile or the bar widget reflects instantly.
  readonly property var hostShell: bar && bar.shell ? bar.shell : null
  readonly property var notificationService: hostShell && typeof hostShell.firstPartyServiceFor === "function"
    ? hostShell.firstPartyServiceFor("omarchy.notifications")
    : null
  readonly property bool dndActive: notificationService ? notificationService.doNotDisturb : false
  property bool idleInhibited: false
  property bool nightLightActive: false
  property bool nightLightAvailable: false
  property bool nightLightPending: false
  property string themeName: ""
  property string backgroundName: ""

  function setBrightness(percent) {
    var clamped = Math.max(1, Math.min(100, Math.round(percent)))
    currentBrightness = clamped
    pendingBrightness = clamped
    brightnessWriteTimer.restart()
  }

  function refresh() {
    if (!brightnessProc.running) brightnessProc.running = true
    if (!idleProc.running) idleProc.running = true
    if (!nightLightPending && !nightLightProc.running) nightLightProc.running = true
    if (!themeProc.running) themeProc.running = true
    if (!backgroundProc.running) backgroundProc.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: brightnessProc
    command: ["bash", "-lc", "command -v brightnessctl >/dev/null || { echo missing; exit; }; cur=$(brightnessctl get); max=$(brightnessctl max); [[ $max -gt 0 ]] && echo $((cur*100/max)) || echo 0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = String(text || "").trim()
        root.currentBrightness = v === "missing" ? -1 : (parseInt(v, 10) || 0)
      }
    }
  }

  Process {
    id: brightnessWriteProc
  }

  Timer {
    id: brightnessWriteTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (brightnessWriteProc.running) { brightnessWriteTimer.restart(); return }
      if (root.pendingBrightness < 0) return
      brightnessWriteProc.command = ["bash", "-lc", "brightnessctl set " + root.pendingBrightness + "% >/dev/null"]
      root.pendingBrightness = -1
      brightnessWriteProc.running = true
    }
  }

  Process {
    id: idleProc
    command: ["bash", "-lc", "if pgrep -x hypridle >/dev/null 2>&1; then echo running; else echo inhibited; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.idleInhibited = String(text || "").trim() === "inhibited"
    }
  }

  Process {
    id: nightLightProc
    command: ["bash", "-lc", "command -v hyprsunset >/dev/null || { echo missing; exit; }; if pgrep -x hyprsunset >/dev/null 2>&1; then hyprctl hyprsunset temperature 2>/dev/null | grep -oE '[0-9]+' | head -1; else echo idle; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var state = String(text || "").trim()
        if (state === "missing") {
          root.nightLightAvailable = false
          root.nightLightActive = false
          return
        }
        root.nightLightAvailable = true
        if (root.nightLightPending) return
        var temp = parseInt(state, 10)
        root.nightLightActive = !isNaN(temp) && temp < 6000
      }
    }
  }

  Process {
    id: nightLightToggleProc
    command: ["omarchy-toggle-nightlight"]
    onExited: {
      root.nightLightPending = false
      if (!nightLightProc.running) nightLightProc.running = true
    }
  }

  Process {
    id: themeProc
    command: ["omarchy-theme-current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeName = String(text || "").trim()
    }
  }

  Process {
    id: themeSetProc
    command: ["bash", "-lc", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\""]
    onExited: root.refresh()
  }

  Process {
    id: backgroundProc
    command: ["omarchy-theme-bg-current"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.backgroundName = String(text || "").trim()
    }
  }

  Process {
    id: backgroundSetProc
    command: ["bash", "-lc", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
    onExited: root.refresh()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰙪"
    fontSize: 12
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    margin: 6
    contentWidth: 320
    contentHeight: layout.implicitHeight + 28

    Column {
      id: layout
      anchors.fill: parent
      spacing: 14

      Column {
        width: parent.width
        spacing: 10
        visible: root.currentBrightness >= 0

        Row {
          width: parent.width
          spacing: 8

          Common.PillButton {
            iconText: root.nightLightActive ? "󰖔" : "󰖙"
            tooltipText: root.nightLightActive ? "Turn off Night Light" : "Turn on Night Light"
            foreground: root.bar.foreground
            horizontalPadding: 8
            verticalPadding: 6
            iconSize: 16
            active: root.nightLightActive
            opacity: root.nightLightAvailable ? 1 : 0.4
            enabled: root.nightLightAvailable
            onClicked: {
              if (nightLightToggleProc.running) return
              root.nightLightActive = !root.nightLightActive
              root.nightLightPending = true
              nightLightToggleProc.running = true
            }
          }

          Common.Slider {
            bar: root.bar
            width: parent.width - 90
            value: Math.max(0, root.currentBrightness / 100)
            minimum: 0.01
            maximum: 1
            step: 0.05
            anchors.verticalCenter: parent.verticalCenter
            onMoved: function(v) { root.setBrightness(v * 100) }
            onReleased: function(v) { root.setBrightness(v * 100) }
          }

          Text {
            text: root.currentBrightness + "%"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            horizontalAlignment: Text.AlignRight
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Grid {
        id: tileGrid
        width: parent.width
        columns: 2
        columnSpacing: 8
        rowSpacing: 8

        Tile {
          width: (tileGrid.width - tileGrid.columnSpacing) / 2
          glyph: root.dndActive ? "󰂛" : "󰂚"
          title: "Do Not Disturb"
          subtitle: root.dndActive ? "On" : "Off"
          active: root.dndActive
          onClicked: {
            if (!root.notificationService) return
            root.notificationService.setDoNotDisturb(!root.notificationService.doNotDisturb)
          }
        }

        Tile {
          width: (tileGrid.width - tileGrid.columnSpacing) / 2
          glyph: root.idleInhibited ? "󰅶" : "󰾪"
          title: "Keep Awake"
          subtitle: root.idleInhibited ? "On" : "Off"
          active: root.idleInhibited
          onClicked: { root.run("omarchy-toggle-idle"); idleProc.running = true }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Row {
        width: parent.width
        spacing: 8

        AppearancePill {
          width: (parent.width - parent.spacing) / 2
          icon: "󰌁"
          label: "Theme"
          currentValue: root.themeName || "—"
          onClicked: {
            root.popupOpen = false
            if (!themeSetProc.running) themeSetProc.running = true
          }
        }

        AppearancePill {
          width: (parent.width - parent.spacing) / 2
          icon: "󰋩"
          label: "Background"
          currentValue: root.backgroundName || "—"
          onClicked: {
            root.popupOpen = false
            if (!backgroundSetProc.running) backgroundSetProc.running = true
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Common.PillButton {
        width: parent.width
        iconText: "󰙪"
        text: "Settings…"
        foreground: root.bar.foreground
        horizontalPadding: 10
        verticalPadding: 8
        onClicked: { root.run("omarchy-launch-settings"); root.popupOpen = false }
      }
    }
  }

  component AppearancePill: Rectangle {
    id: appearancePill

    property string icon: ""
    property string label: ""
    property string currentValue: "—"

    signal clicked()

    implicitHeight: 56
    height: 56
    radius: 6
    color: appearanceArea.containsMouse
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04)
    border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 120 } }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 10
      spacing: 2

      Text {
        text: appearancePill.icon.length > 0 ? appearancePill.icon + " " + appearancePill.label : appearancePill.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: appearancePill.currentValue
        color: Qt.darker(root.bar.foreground, 1.35)
        font.family: root.bar.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        width: parent.width
      }
    }

    MouseArea {
      id: appearanceArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: appearancePill.clicked()
    }
  }

  component Tile: Rectangle {
    id: tile

    property string glyph: ""
    property string title: ""
    property string subtitle: ""
    property bool active: false
    property bool tileEnabled: true

    signal clicked()

    implicitHeight: 56
    radius: 6
    color: tileArea.containsMouse
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, active ? 0.10 : 0.04)
    border.color: active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35) : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
    border.width: 1
    opacity: tileEnabled ? 1 : 0.4

    Behavior on color { ColorAnimation { duration: 120 } }

    Column {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 10
      spacing: 2

      Text {
        text: tile.glyph.length > 0 ? tile.glyph + " " + tile.title : tile.title
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 11
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        text: tile.subtitle
        color: Qt.darker(root.bar.foreground, 1.35)
        font.family: root.bar.fontFamily
        font.pixelSize: 10
        elide: Text.ElideRight
        width: parent.width
      }
    }

    MouseArea {
      id: tileArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: tile.tileEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: tile.tileEnabled
      onClicked: tile.clicked()
    }
  }
}
