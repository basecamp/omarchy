import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
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

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real currentVolume: sink && sink.audio && isFinite(sink.audio.volume) ? sink.audio.volume : 0
  readonly property bool sinkMuted: sink && sink.audio ? sink.audio.muted : false
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  property int currentBrightness: -1
  property int pendingBrightness: -1

  property bool dndActive: false
  property bool idleInhibited: false
  property bool nightLightActive: false
  property bool nightLightAvailable: false
  property string themeName: ""

  readonly property bool powerProfileAvailable: PowerProfiles.hasPerformanceProfile || PowerProfiles.profile === PowerProfile.PowerSaver || PowerProfiles.profile === PowerProfile.Balanced
  readonly property int currentProfile: PowerProfiles.profile

  function setVolume(value) {
    if (!sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, value))
  }

  function toggleMute() {
    if (!sink || !sink.audio) return
    sink.audio.muted = !sink.audio.muted
  }

  function setBrightness(percent) {
    var clamped = Math.max(1, Math.min(100, Math.round(percent)))
    currentBrightness = clamped
    pendingBrightness = clamped
    brightnessWriteTimer.restart()
  }

  function refresh() {
    if (!brightnessProc.running) brightnessProc.running = true
    if (!dndProc.running) dndProc.running = true
    if (!idleProc.running) idleProc.running = true
    if (!nightLightProc.running) nightLightProc.running = true
    if (!themeProc.running) themeProc.running = true
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
    id: dndProc
    command: ["bash", "-lc", "if command -v makoctl >/dev/null && makoctl mode 2>/dev/null | grep -q '^do-not-disturb$'; then echo on; else echo off; fi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.dndActive = String(text || "").trim() === "on"
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
        var temp = parseInt(state, 10)
        root.nightLightActive = !isNaN(temp) && temp < 6000
      }
    }
  }

  Process {
    id: themeProc
    command: ["bash", "-lc", "readlink ~/.config/omarchy/current/theme 2>/dev/null | xargs -r basename"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeName = String(text || "").trim()
    }
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
    fontSize: 14
    tooltipText: "Quick Settings"
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  Common.PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: 320
    contentHeight: layout.implicitHeight + 28

    Column {
      id: layout
      anchors.fill: parent
      spacing: 14

      Text {
        text: "Quick settings"
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        font.bold: true
      }

      Column {
        width: parent.width
        spacing: 10
        visible: root.sink !== null

        Row {
          width: parent.width
          spacing: 8

          Common.PillButton {
            iconText: root.sinkMuted ? "󰝟" : "󰕾"
            foreground: root.bar.foreground
            horizontalPadding: 8
            verticalPadding: 6
            iconSize: 16
            onClicked: root.toggleMute()
          }

          Common.Slider {
            bar: root.bar
            width: parent.width - 90
            value: root.currentVolume
            minimum: 0
            maximum: 1
            step: 0.05
            anchors.verticalCenter: parent.verticalCenter
            onMoved: function(v) { root.setVolume(v) }
            onReleased: function(v) { root.setVolume(v) }
          }

          Text {
            text: Math.round(root.currentVolume * 100) + "%"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            horizontalAlignment: Text.AlignRight
          }
        }

        Row {
          width: parent.width
          spacing: 8
          visible: root.currentBrightness >= 0

          Common.PillButton {
            iconText: "󰃠"
            foreground: root.bar.foreground
            horizontalPadding: 8
            verticalPadding: 6
            iconSize: 16
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
          onClicked: { root.run("omarchy-toggle-notification-silencing"); dndProc.running = true }
        }

        Tile {
          width: (tileGrid.width - tileGrid.columnSpacing) / 2
          glyph: root.nightLightActive ? "󰖔" : "󰖙"
          title: "Night Light"
          subtitle: !root.nightLightAvailable ? "—" : (root.nightLightActive ? "On" : "Off")
          active: root.nightLightActive
          tileEnabled: root.nightLightAvailable
          onClicked: { root.run("omarchy-toggle-nightlight"); nightLightProc.running = true }
        }

        Tile {
          width: (tileGrid.width - tileGrid.columnSpacing) / 2
          glyph: root.idleInhibited ? "󰅶" : "󰾪"
          title: "Keep Awake"
          subtitle: root.idleInhibited ? "On" : "Off"
          active: root.idleInhibited
          onClicked: { root.run("omarchy-toggle-idle"); idleProc.running = true }
        }

        Tile {
          width: (tileGrid.width - tileGrid.columnSpacing) / 2
          glyph: "󰔎"
          title: "Theme"
          subtitle: root.themeName || "—"
          onClicked: { root.run("omarchy-menu themes"); root.popupOpen = false }
        }
      }

      Rectangle {
        visible: root.powerProfileAvailable
        width: parent.width
        height: 1
        color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
      }

      Column {
        width: parent.width
        spacing: 6
        visible: root.powerProfileAvailable

        Text {
          text: "Power profile"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Repeater {
          model: [
            { profile: PowerProfile.PowerSaver, label: "Power Saver", glyph: "󰌪" },
            { profile: PowerProfile.Balanced, label: "Balanced", glyph: "󰗑" },
            { profile: PowerProfile.Performance, label: "Performance", glyph: "󰓅" }
          ]

          ProfileButton {
            required property var modelData
            width: parent.width
            profile: modelData.profile
            label: modelData.label
            glyph: modelData.glyph
            profileEnabled: modelData.profile !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
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

  component ProfileButton: Rectangle {
    id: profileButton

    property int profile: PowerProfile.Balanced
    property string label: ""
    property string glyph: ""
    property bool profileEnabled: true
    readonly property bool active: root.currentProfile === profile

    height: 34
    radius: 4
    color: profileArea.pressed
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
      : profileArea.containsMouse
        ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
        : (active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18) : "transparent")
    border.color: active ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
    border.width: active ? 1 : 0
    opacity: profileEnabled ? 1 : 0.4

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      spacing: 8

      Text {
        text: profileButton.glyph
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 14
        width: 18
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: profileButton.label
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
        width: parent.width - 18 - 14 - 16
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: profileButton.active ? "󰄬" : ""
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 13
        width: 14
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: profileArea
      anchors.fill: parent
      hoverEnabled: true
      enabled: profileButton.profileEnabled
      cursorShape: profileButton.profileEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: PowerProfiles.profile = profileButton.profile
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
      ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.16)
      : (active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.10)
                : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.04))
    border.color: active ? root.bar.foreground : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
    border.width: 1
    opacity: tileEnabled ? 1 : 0.4

    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      Text {
        text: tile.glyph
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 18
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        width: parent.width - parent.children[0].implicitWidth - 8

        Text {
          text: tile.title
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          text: tile.subtitle
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: 10
          elide: Text.ElideRight
          width: parent.width
        }
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
