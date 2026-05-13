import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../common" as Common

Item {
  id: root

  property QtObject bar: null
  property string moduleName: "audioPanel"
  property var settings: ({})

  property bool popupOpen: false

  function closePopout() { popupOpen = false }

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var audioSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isSink && !node.isStream && node.audio) list.push(node)
    }
    return list
  }

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var node = nodes[i]
      if (node && node.isStream && !node.isSink && node.audio) list.push(node)
    }
    return list
  }

  readonly property real currentVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

  readonly property string volumeIcon: {
    if (!sink || !sink.audio) return ""
    if (muted) return "󰸈"
    var v = currentVolume
    if (v >= 0.67) return "󰕾"
    if (v >= 0.34) return "󰖀"
    if (v > 0) return "󰕿"
    return "󰸈"
  }

  function setVolume(v) {
    if (!sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function setDefaultSink(node) {
    Pipewire.preferredDefaultAudioSink = node
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker { objects: root.audioSinks }
  PwObjectTracker { objects: root.audioStreams }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.volumeIcon
    tooltipText: root.sink ? (root.sink.description || root.sink.nickname || "Audio") + " · " + Math.round(root.currentVolume * 100) + "%" : "No audio"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleMute()
      else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-audio")
      else root.popupOpen = !root.popupOpen
    }

    onWheelMoved: function(delta) {
      var step = 0.05
      root.setVolume(root.currentVolume + (delta > 0 ? step : -step))
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 340
    contentHeight: panelColumn.implicitHeight + 28

    Column {
      id: panelColumn
      anchors.fill: parent
      spacing: 12

      // Master volume
      Row {
        width: parent.width
        spacing: 10

        Text {
          text: root.volumeIcon
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: 18
          anchors.verticalCenter: parent.verticalCenter

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleMute()
          }
        }

        Common.Slider {
          bar: root.bar
          width: parent.width - 50
          anchors.verticalCenter: parent.verticalCenter
          minimum: 0
          maximum: 1
          step: 0.05
          value: root.currentVolume
          opacity: root.muted ? 0.5 : 1.0

          onMoved: function(v) { root.setVolume(v) }
        }
      }

      // Output device picker
      Column {
        spacing: 4
        width: parent.width
        visible: root.audioSinks.length > 0

        Text {
          text: "Output"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Repeater {
          model: root.audioSinks

          Common.PillButton {
            required property var modelData

            width: parent.width
            text: modelData ? (modelData.description || modelData.nickname || modelData.name || "Unknown") : ""
            iconText: root.sinkGlyph(modelData)
            foreground: root.bar.foreground
            horizontalPadding: 10
            verticalPadding: 6
            active: root.sink && modelData && root.sink.id === modelData.id
            onClicked: { root.setDefaultSink(modelData); }
          }
        }
      }

      // Per-app streams
      Column {
        spacing: 4
        width: parent.width
        visible: root.audioStreams.length > 0

        Text {
          text: "Playing"
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Repeater {
          model: root.audioStreams

          Row {
            required property var modelData

            width: parent.width
            spacing: 8

            Text {
              text: modelData && modelData.properties ? (modelData.properties["application.name"] || modelData.properties["node.name"] || "Stream") : "Stream"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
              width: 110
              anchors.verticalCenter: parent.verticalCenter
            }

            Common.Slider {
              bar: root.bar
              width: parent.width - 124
              anchors.verticalCenter: parent.verticalCenter
              minimum: 0
              maximum: 1.5
              step: 0.05
              value: modelData && modelData.audio ? modelData.audio.volume : 0

              onMoved: function(v) {
                if (modelData && modelData.audio) modelData.audio.volume = v
              }
            }
          }
        }
      }
    }
  }

  function sinkGlyph(node) {
    if (!node) return ""
    var blob = String([
      node.name, node.description, node.nickname,
      node.properties ? node.properties["device.icon-name"] : "",
      node.properties ? node.properties["device.product.name"] : ""
    ].join(" ")).toLowerCase()
    if (blob.indexOf("headphone") !== -1 || blob.indexOf("headset") !== -1) return ""
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
    return "󰓃"
  }
}
