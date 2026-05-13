import QtQuick
import Quickshell
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

      Text {
        id: labelText
        text: root.title + (root.artist ? "  ·  " + root.artist : "")
        color: root.bar.foreground
        font.family: root.bar.fontFamily
        font.pixelSize: 12
        anchors.verticalCenter: parent.verticalCenter

        property bool needsScroll: implicitWidth > scrollClip.width
        x: needsScroll ? scrollAnim.position : 0

        NumberAnimation on x {
          id: scrollAnim
          property real position: 0
          running: labelText.needsScroll && !root.popupOpen
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
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      if (mouse.button === Qt.MiddleButton) {
        if (root.activePlayer.canGoNext) root.activePlayer.next()
      } else if (mouse.button === Qt.RightButton) {
        root.popupOpen = !root.popupOpen
      } else {
        if (root.activePlayer.canTogglePlaying) root.activePlayer.togglePlaying()
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.activePlayer.canGoPrevious) root.activePlayer.previous()
      else if (wheel.angleDelta.y < 0 && root.activePlayer.canGoNext) root.activePlayer.next()
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
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
