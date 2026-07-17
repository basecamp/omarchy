import QtQuick
import qs.Commons

Item {
  id: root

  property string text: ""
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property color color: Color.foreground
  property real targetExtent: Math.min(width, height) * 0.82
  property bool debugBounds: false

  readonly property real baseTightWidth: Math.max(1, baseMetrics.tightBoundingRect.width)
  readonly property real baseTightHeight: Math.max(1, baseMetrics.tightBoundingRect.height)
  readonly property real normalizedScale: Math.min(1.5, targetExtent / Math.max(baseTightWidth, baseTightHeight))
  readonly property int normalizedFontSize: Math.max(1, Math.round(fontSize * normalizedScale))
  readonly property real tightWidth: Math.max(1, glyphMetrics.tightBoundingRect.width)
  readonly property real tightHeight: Math.max(1, glyphMetrics.tightBoundingRect.height)
  readonly property real horizontalCorrection: glyph.implicitWidth / 2 - (glyphMetrics.tightBoundingRect.x + tightWidth / 2)
  readonly property real verticalCorrection: glyph.implicitHeight / 2 - (glyph.baselineOffset + glyphMetrics.tightBoundingRect.y + tightHeight / 2)
  readonly property real paintedCenterX: glyph.x + glyphMetrics.tightBoundingRect.x + tightWidth / 2
  readonly property real paintedCenterY: glyph.y + glyph.baselineOffset + glyphMetrics.tightBoundingRect.y + tightHeight / 2

  TextMetrics {
    id: baseMetrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: root.text
  }

  TextMetrics {
    id: glyphMetrics
    font.family: root.fontFamily
    font.pixelSize: root.normalizedFontSize
    text: root.text
  }

  Text {
    id: glyph
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: root.horizontalCorrection
    anchors.verticalCenterOffset: root.verticalCorrection
    text: root.text
    color: root.color
    font.family: root.fontFamily
    font.pixelSize: root.normalizedFontSize
    renderType: Text.NativeRendering
  }

  Rectangle {
    visible: root.debugBounds
    anchors.fill: parent
    color: "transparent"
    border.width: 1
    border.color: "#4488ff"
  }
}
