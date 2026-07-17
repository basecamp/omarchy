import QtQuick
import Quickshell
import qs.Commons

WidgetButton {
  id: root

  property Component iconComponent: null
  property real opticalSize: Style.bar.iconCanvas
  property bool debugOpticalBounds: Quickshell.env("OMARCHY_DEBUG_BAR_ICONS") === "1"
  readonly property real opticalCenterErrorX: glyph.visible ? glyph.paintedCenterX - opticalCanvas.width / 2 : 0
  readonly property real opticalCenterErrorY: glyph.visible ? glyph.paintedCenterY - opticalCanvas.height / 2 : 0

  labelVisible: false
  hasVisualContent: text !== "" || iconComponent !== null
  fontSize: Style.font.body
  fixedWidth: vertical ? -1 : Style.bar.iconSlot
  fixedHeight: vertical ? Style.bar.iconSlot : -1

  Item {
    id: opticalCanvas
    anchors.centerIn: parent
    width: root.opticalSize
    height: root.opticalSize

    OpticalGlyph {
      id: glyph
      anchors.fill: parent
      visible: root.iconComponent === null
      text: root.text
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      color: root.active && root.useActiveColor ? root.activeColor : root.foreground
      rotation: root.textRotation
      debugBounds: root.debugOpticalBounds
    }

    Loader {
      anchors.fill: parent
      visible: root.iconComponent !== null
      sourceComponent: root.iconComponent
    }

    Rectangle {
      visible: root.debugOpticalBounds && root.iconComponent !== null
      anchors.fill: parent
      color: "transparent"
      border.width: 1
      border.color: "#4488ff"
    }
  }

  Rectangle {
    visible: root.debugOpticalBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#ff4455"
  }
}
