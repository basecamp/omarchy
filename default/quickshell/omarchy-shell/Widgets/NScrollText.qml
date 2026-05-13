import QtQuick
import qs.Commons

// Noctalia compat shim. Auto-scrolling label.
Item {
  id: root

  property string text: ""
  property real maxWidth: 200
  property real pointSize: Style.fontSizeM
  property int scrollMode: NScrollText.ScrollMode.Hover
  property bool forcedHover: false
  property real fadeExtent: 0.1
  property real fadeCornerRadius: 0
  property bool fadeRoundLeftCorners: false
  property bool fadeRoundRightCorners: false
  property color textColor: Color.mOnSurface

  enum ScrollMode { Always, Hover, Never }

  implicitHeight: label.implicitHeight
  implicitWidth: Math.min(maxWidth, label.implicitWidth)
  clip: true

  readonly property bool overflowing: label.implicitWidth > width
  readonly property bool shouldScroll: {
    if (!overflowing) return false
    if (scrollMode === NScrollText.ScrollMode.Always) return true
    if (scrollMode === NScrollText.ScrollMode.Hover) return forcedHover
    return false
  }

  Text {
    id: label
    text: root.text
    color: root.textColor
    font.family: "JetBrainsMono Nerd Font"
    font.pixelSize: root.pointSize
    verticalAlignment: Text.AlignVCenter
    height: parent.height
    anchors.verticalCenter: parent.verticalCenter

    NumberAnimation on x {
      id: scrollAnim
      running: root.shouldScroll
      loops: Animation.Infinite
      duration: Math.max(5000, label.implicitWidth * 22)
      from: root.width
      to: -label.implicitWidth
      easing.type: Easing.Linear
    }

    onShouldScrollChanged: if (!root.shouldScroll) x = 0
  }
}
