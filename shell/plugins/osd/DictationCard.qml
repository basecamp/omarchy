import QtQuick
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  property var dictation: null
  property bool opened: false

  readonly property bool transcribing: dictation && dictation.transcribing
  readonly property int gap: Style.spacing.xl

  width: Style.space(320)
  height: Style.space(54)
  radius: Style.cornerRadius
  color: Util.alpha(Color.background, 0.97)
  borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  opacity: opened ? 1 : 0
  scale: opened ? 1 : 0.98

  Behavior on opacity {
    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
  }

  Behavior on scale {
    NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
  }

  Row {
    anchors.centerIn: parent
    spacing: root.gap

    Text {
      width: Style.space(18)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignHCenter
      text: root.transcribing ? "󰔟" : "󰍬"
      color: root.transcribing ? Color.accent : Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Text {
      width: Style.space(84)
      anchors.verticalCenter: parent.verticalCenter
      text: root.transcribing ? "Transcribing" : "Listening"
      color: root.transcribing ? Util.alpha(Color.popups.text, 0.7) : Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      width: root.transcribing ? Style.space(156) : Style.space(112)
      height: Style.space(22)
      anchors.verticalCenter: parent.verticalCenter

      Behavior on width {
        NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
      }

      Canvas {
        id: bars

        anchors.fill: parent
        visible: !root.transcribing

        onPaint: {
          var ctx = getContext("2d")
          ctx.clearRect(0, 0, width, height)

          var levels = root.dictation ? root.dictation.levels : []
          var count = levels.length
          if (count === 0) return

          var barWidth = Style.spaceReal(3)
          var gap = (width - count * barWidth) / (count - 1)
          for (var i = 0; i < count; i++) {
            var level = levels[i]
            var barHeight = Math.max(Style.spaceReal(2), level * (height - Style.spaceReal(2)))
            ctx.fillStyle = level > 0.85 ? Color.urgent : Color.accent
            ctx.globalAlpha = 0.35 + level * 0.65
            ctx.beginPath()
            ctx.roundedRect(i * (barWidth + gap), height - barHeight, barWidth, barHeight, barWidth / 2, barWidth / 2)
            ctx.fill()
          }
          ctx.globalAlpha = 1
        }

        Connections {
          target: root.dictation
          function onLevelsChanged() { bars.requestPaint() }
        }

        Connections {
          target: Color
          function onAccentChanged() { bars.requestPaint() }
          function onUrgentChanged() { bars.requestPaint() }
        }
      }

      Rectangle {
        id: sweepTrack

        width: parent.width
        height: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Util.alpha(Color.popups.text, 0.09)
        visible: root.transcribing
        clip: true

        Rectangle {
          id: sweep

          width: sweepTrack.width * 0.38
          height: sweepTrack.height
          radius: sweepTrack.radius
          color: Color.accent

          XAnimator on x {
            running: root.transcribing
            loops: Animation.Infinite
            from: -sweep.width
            to: sweepTrack.width
            duration: 1150
            easing.type: Easing.InOutQuad
          }
        }
      }
    }

    Text {
      visible: !root.transcribing
      width: visible ? Style.space(34) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: {
        var elapsed = root.dictation ? root.dictation.elapsed : 0
        var minutes = Math.floor(elapsed / 60)
        var seconds = elapsed % 60
        return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
      }
      color: Util.alpha(Color.popups.text, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
    }
  }
}
