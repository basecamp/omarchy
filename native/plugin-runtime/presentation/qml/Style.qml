pragma Singleton
import QtQuick

QtObject {
  readonly property int cornerRadius: 10
  readonly property int normalBorderWidth: 1
  readonly property int gapsOut: 16
  readonly property var spacing: ({xs: 6, sm: 10, md: 16, lg: 24, panelPadding: 24, controlPaddingY: 8, rowPaddingX: 12})
  readonly property var font: ({
    menuFamily: "sans-serif",
    family: "sans-serif",
    icon: 16,
    display: 28,
    displayLarge: 44,
    heading: 24,
    title: 20,
    body: 15,
    bodySmall: 13,
    caption: 12
  })

  function space(value) { return value }
  function hoverFillFor(foreground, accent) {
    return Qt.rgba(accent.r, accent.g, accent.b, 0.12)
  }
  function selectedFillFor(foreground, accent) {
    return Qt.rgba(accent.r, accent.g, accent.b, 0.20)
  }
}
