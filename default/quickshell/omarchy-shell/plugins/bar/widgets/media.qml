import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "media"
  property var settings: ({})

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: {
    var playing = null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue
      if (p.isPlaying) return p
      if (!playing && p.trackTitle) playing = p
    }
    return playing
  }

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  property bool popupOpen: false

  function closePopout() { popupOpen = false }
  property real maxLabelWidth: 180

  // Live FFT from the default sink, fed by `cava` running in raw mode.
  // Gated on playback so it doesn't burn CPU when nothing is playing.
  // If cava isn't installed the script exits 1 and spectrumValues stays
  // empty, which hides the visualizer everywhere it's used.
  readonly property int spectrumBars: 28
  readonly property bool spectrumWanted: (activePlayer && activePlayer.isPlaying) || popupOpen
  property var spectrumValues: []

  Process {
    id: cavaProc
    running: root.spectrumWanted && root.bar !== null
    command: ["bash", "-lc",
      (root.bar ? root.bar.shellQuote(root.bar.omarchyPath + "/default/quickshell/omarchy-shell/scripts/cava-bars.sh") : "")
        + " " + root.spectrumBars]
    stdout: SplitParser {
      onRead: function(line) {
        var trimmed = String(line).trim()
        if (!trimmed) return
        var parts = trimmed.split(/\s+/)
        var out = new Array(parts.length)
        for (var i = 0; i < parts.length; i++) {
          var v = parseInt(parts[i], 10)
          out[i] = isNaN(v) ? 0 : Math.min(1, v / 255)
        }
        root.spectrumValues = out
      }
    }
    onRunningChanged: if (!running) root.spectrumValues = []
  }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + 14 : 0
  implicitHeight: bar ? bar.barSize : 26

  Row {
    id: row
    anchors.centerIn: parent
    spacing: 6

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      text: root.playIcon
      color: activePlayer && activePlayer.isPlaying ? root.bar.foreground : Qt.darker(root.bar.foreground, 1.5)
      font.family: root.bar.fontFamily
      font.pixelSize: 12

      Behavior on color { ColorAnimation { duration: 160 } }
    }

    Item {
      id: scrollClip
      width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
      height: glyph.height
      clip: true
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.bar.vertical && root.title !== ""

      // cliamp-style FFT bars layered behind the scrolling title at low
      // opacity. Hidden on vertical bars where the label itself is hidden,
      // and stays hidden when cava isn't installed (spectrumValues is empty).
      Row {
        id: barViz
        anchors.fill: parent
        spacing: 1
        z: -1
        visible: root.spectrumValues.length > 0 && !root.bar.vertical
        opacity: (root.activePlayer && root.activePlayer.isPlaying) ? 0.35 : 0.0

        Behavior on opacity { NumberAnimation { duration: 250 } }

        Repeater {
          model: root.spectrumValues
          delegate: Item {
            width: Math.max(1, (barViz.width - (root.spectrumValues.length - 1)) / root.spectrumValues.length)
            height: barViz.height

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.rightMargin: 0
              height: Math.max(1, Math.min(1, modelData) * (barViz.height - 2))
              color: root.bar.foreground
              radius: 1

              Behavior on height {
                NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
              }
            }
          }
        }
      }

      Text {
        id: labelText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width

        NumberAnimation on x {
          id: scrollAnim
          running: labelText.needsScroll && !root.popupOpen && !root.bar.vertical
          loops: Animation.Infinite
          duration: Math.max(6000, labelText.implicitWidth * 25)
          from: scrollClip.width
          to: -labelText.implicitWidth
          easing.type: Easing.Linear
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.activePlayer.canGoNext) root.activePlayer.next()
      } else if (mouse.button === Qt.RightButton) {
        if (root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying()
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.activePlayer.canGoPrevious) root.activePlayer.previous()
      else if (wheel.angleDelta.y < 0 && root.activePlayer.canGoNext) root.activePlayer.next()
    }
  }

  Common.PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: 320
    contentHeight: column.implicitHeight + 28

    Column {
      id: column
      anchors.fill: parent
      spacing: 10

      Row {
        spacing: 10
        width: parent.width

        Rectangle {
          width: 64
          height: 64
          radius: 4
          color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.08)
          border.color: Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.2)
          border.width: 1

          Image {
            anchors.fill: parent
            anchors.margins: 2
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 28
          }
        }

        Column {
          spacing: 4
          width: parent.width - 74

          Text {
            text: root.title || "Nothing playing"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: 13
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.artist
            color: Qt.darker(root.bar.foreground, 1.3)
            font.family: root.bar.fontFamily
            font.pixelSize: 11
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: 10
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Item {
        id: popupViz
        width: parent.width
        height: 36
        visible: root.spectrumValues.length > 0

        Row {
          anchors.fill: parent
          spacing: 2

          Repeater {
            model: root.spectrumValues

            delegate: Item {
              width: Math.max(1, (popupViz.width - (root.spectrumValues.length - 1) * 2) / root.spectrumValues.length)
              height: popupViz.height

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(2, Math.min(1, modelData) * (popupViz.height - 2))
                color: root.bar.foreground
                opacity: root.activePlayer && root.activePlayer.isPlaying ? 0.85 : 0.25
                radius: 1

                Behavior on height {
                  NumberAnimation { duration: 60; easing.type: Easing.OutQuad }
                }
                Behavior on opacity { NumberAnimation { duration: 250 } }
              }
            }
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6

        Common.PillButton {
          iconText: "󰒮"
          foreground: root.bar.foreground
          horizontalPadding: 10
          verticalPadding: 6
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.activePlayer) root.activePlayer.previous()
        }

        Common.PillButton {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.bar.foreground
          horizontalPadding: 14
          verticalPadding: 6
          iconSize: 18
          enabled: root.activePlayer && root.activePlayer.canTogglePlaying
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
        }

        Common.PillButton {
          iconText: "󰒭"
          foreground: root.bar.foreground
          horizontalPadding: 10
          verticalPadding: 6
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.activePlayer) root.activePlayer.next()
        }
      }
    }
  }
}
