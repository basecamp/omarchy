import QtQuick
import QtQuick.Controls
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

  readonly property var candidateSinks: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && !n.isSink && !n.isStream && n.audio) {
        var name = n.name || ""
        if (name === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  readonly property var candidateStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n)) list.push(n)
    }
    return list
  }

  // Identify true playback streams without reading node.properties here:
  // PwNode.properties is invalid until the node is bound, and reading it while
  // capture streams are appearing (for example, when Voxtype starts recording)
  // can destabilize Quickshell's Pipewire service. `type` mirrors media.class
  // and is safe enough for pre-bind filtering.
  function isPlaybackStream(node) {
    if (!node) return false
    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Output") !== -1
  }

  readonly property var audioSinks: {
    var list = []
    for (var i = 0; i < candidateSinks.length; i++)
      if (candidateSinks[i].audio) list.push(candidateSinks[i])
    return list
  }

  readonly property var audioSources: candidateSources

  readonly property var audioStreams: {
    var list = []
    for (var i = 0; i < candidateStreams.length; i++)
      if (candidateStreams[i].audio) list.push(candidateStreams[i])
    return list
  }

  readonly property real outputVolume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool outputMuted: sink && sink.audio ? sink.audio.muted : false
  readonly property real inputVolume: source && source.audio ? source.audio.volume : 0
  readonly property bool inputMuted: source && source.audio ? source.audio.muted : false

  function outputIcon() {
    // Match the old Waybar pulseaudio glyph set. The Material Design speaker
    // icons render visually smaller in JetBrainsMono Nerd Font.
    if (!sink || !sink.audio) return ""
    if (outputMuted) return ""
    var v = outputVolume
    if (v >= 0.67) return ""
    if (v >= 0.34) return ""
    if (v > 0) return ""
    return ""
  }

  function inputIcon() {
    if (!source || !source.audio) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  function setOutputVolume(v) {
    if (!sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function setInputVolume(v) {
    if (!source || !source.audio) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
  }

  function toggleInputMute() {
    if (source && source.audio) source.audio.muted = !source.audio.muted
  }

  function setDefaultSink(node) { Pipewire.preferredDefaultAudioSink = node }
  function setDefaultSource(node) { Pipewire.preferredDefaultAudioSource = node }

  function nodeLabel(node) {
    if (!node) return "Unknown"
    return node.description || node.nickname || node.name || "Unknown"
  }

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function sinkGlyph(node) {
    if (!node) return "󰓃"
    var p = nodeProps(node)
    var blob = String([
      node.name, node.description, node.nickname,
      p["device.icon-name"] || "",
      p["device.product.name"] || ""
    ].join(" ")).toLowerCase()
    if (blob.indexOf("headphone") !== -1 || blob.indexOf("headset") !== -1) return "󰋋"
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
    return "󰓃"
  }

  function sourceGlyph(node) {
    if (!node) return "󰍬"
    var p = nodeProps(node)
    var blob = String([
      node.name, node.description, node.nickname,
      p["device.icon-name"] || ""
    ].join(" ")).toLowerCase()
    if (blob.indexOf("headset") !== -1) return "󰋋"
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
    return "󰍬"
  }

  function streamLabel(node) {
    if (!node) return "Stream"
    var p = nodeProps(node)
    return p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name || "Stream"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  PwObjectTracker { objects: root.candidateSinks }
  PwObjectTracker { objects: root.candidateSources }
  PwObjectTracker { objects: root.audioStreams }

  Common.WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.outputIcon()
    fontSize: 12
    tooltipText: root.sink ? root.nodeLabel(root.sink) + " · " + Math.round(root.outputVolume * 100) + "%" : "No audio"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleOutputMute()
      else if (b === Qt.MiddleButton) root.bar.run("omarchy-launch-audio")
      else root.popupOpen = !root.popupOpen
    }

    onWheelMoved: function(delta) {
      var step = 0.05
      root.setOutputVolume(root.outputVolume + (delta > 0 ? step : -step))
    }
  }

  Common.PopupCard {
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: 380
    contentHeight: Math.min(560, panelColumn.implicitHeight + 28)

    ScrollView {
      id: scrollArea
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      ScrollBar.vertical.policy: ScrollBar.AsNeeded

      Column {
        id: panelColumn
        width: scrollArea.availableWidth
        spacing: 14

        // ---- Output ----
        Column {
          width: parent.width
          spacing: 6

          Row {
            width: parent.width
            spacing: 8

            Text {
              text: "Output"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.sink ? "· " + root.nodeLabel(root.sink) : ""
              color: Qt.darker(root.bar.foreground, 1.8)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
              width: parent.width - 70
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: 8

            Text {
              id: outputIconText
              text: root.outputIcon()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 16
              width: 22
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.outputMuted ? 0.5 : 1.0

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleOutputMute()
              }
            }

            Common.Slider {
              id: outputSlider
              bar: root.bar
              width: parent.width - outputIconText.width - outputPercent.width - 16
              anchors.verticalCenter: parent.verticalCenter
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.outputVolume
              opacity: root.outputMuted ? 0.5 : 1.0
              enabled: !!root.sink

              onMoved: function(v) { root.setOutputVolume(v) }
            }

            Text {
              id: outputPercent
              text: Math.round((outputSlider.dragging ? outputSlider.liveValue : root.outputVolume) * 100) + "%"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              width: 36
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.outputMuted ? 0.5 : 1.0
            }
          }

          Repeater {
            model: root.audioSinks

            Rectangle {
              required property var modelData

              readonly property bool active: root.sink && modelData && root.sink.id === modelData.id

              width: panelColumn.width
              height: deviceRow.implicitHeight + 10
              radius: 4
              color: deviceArea.pressed
                ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
                : deviceArea.containsMouse
                  ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
                  : (active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18) : "transparent")

              Behavior on color { ColorAnimation { duration: 120 } }

              Row {
                id: deviceRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: root.sinkGlyph(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 14
                  width: 18
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.nodeLabel(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  width: parent.width - 18 - 14 - 16
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: active ? "󰄬" : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 13
                  width: 14
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: deviceArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setDefaultSink(modelData)
              }
            }
          }
        }

        // ---- Input ----
        Column {
          width: parent.width
          spacing: 6
          visible: root.audioSources.length > 0 || !!root.source

          Row {
            width: parent.width
            spacing: 8

            Text {
              text: "Input"
              color: Qt.darker(root.bar.foreground, 1.5)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              text: root.source ? "· " + root.nodeLabel(root.source) : ""
              color: Qt.darker(root.bar.foreground, 1.8)
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              elide: Text.ElideRight
              width: parent.width - 56
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: 8
            visible: !!root.source

            Text {
              id: inputIconText
              text: root.inputIcon()
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 16
              width: 22
              horizontalAlignment: Text.AlignHCenter
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.inputMuted ? 0.5 : 1.0

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleInputMute()
              }
            }

            Common.Slider {
              id: inputSlider
              bar: root.bar
              width: parent.width - inputIconText.width - inputPercent.width - 16
              anchors.verticalCenter: parent.verticalCenter
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.inputVolume
              opacity: root.inputMuted ? 0.5 : 1.0
              enabled: !!root.source

              onMoved: function(v) { root.setInputVolume(v) }
            }

            Text {
              id: inputPercent
              text: Math.round((inputSlider.dragging ? inputSlider.liveValue : root.inputVolume) * 100) + "%"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: 11
              width: 36
              horizontalAlignment: Text.AlignRight
              anchors.verticalCenter: parent.verticalCenter
              opacity: root.inputMuted ? 0.5 : 1.0
            }
          }

          Repeater {
            model: root.audioSources

            Rectangle {
              required property var modelData

              readonly property bool active: root.source && modelData && root.source.id === modelData.id

              width: panelColumn.width
              height: sourceRow.implicitHeight + 10
              radius: 4
              color: sourceArea.pressed
                ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.22)
                : sourceArea.containsMouse
                  ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
                  : (active ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.18) : "transparent")

              Behavior on color { ColorAnimation { duration: 120 } }

              Row {
                id: sourceRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                Text {
                  text: root.sourceGlyph(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 14
                  width: 18
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: root.nodeLabel(modelData)
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 12
                  elide: Text.ElideRight
                  width: parent.width - 18 - 14 - 16
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  text: active ? "󰄬" : ""
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: 13
                  width: 14
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: sourceArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setDefaultSource(modelData)
              }
            }
          }
        }

        // ---- Per-app streams ----
        Column {
          width: parent.width
          spacing: 6
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

            Item {
              required property var modelData

              readonly property real streamVolume: modelData && modelData.audio ? modelData.audio.volume : 0
              readonly property bool streamMuted: modelData && modelData.audio ? modelData.audio.muted : false

              width: panelColumn.width
              height: streamColumn.implicitHeight + 4

              Column {
                id: streamColumn
                width: parent.width
                spacing: 2

                Row {
                  width: parent.width
                  spacing: 6

                  Text {
                    id: streamMuteIcon
                    text: streamMuted ? "󰝟" : "󰕾"
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: 12
                    width: 14
                    horizontalAlignment: Text.AlignHCenter
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: streamMuted ? 0.5 : 1.0

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (modelData && modelData.audio) modelData.audio.muted = !modelData.audio.muted
                      }
                    }
                  }

                  Text {
                    text: root.streamLabel(modelData)
                    color: root.bar.foreground
                    font.family: root.bar.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    width: parent.width - streamMuteIcon.width - streamPct.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    id: streamPct
                    text: Math.round(streamVolume * 100) + "%"
                    color: Qt.darker(root.bar.foreground, 1.5)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 11
                    width: 36
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                Common.Slider {
                  bar: root.bar
                  width: parent.width
                  minimum: 0
                  maximum: 1.5
                  step: 0.05
                  value: streamVolume
                  opacity: streamMuted ? 0.5 : 1.0

                  onMoved: function(v) {
                    if (modelData && modelData.audio) modelData.audio.volume = v
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
