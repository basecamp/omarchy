pragma Singleton
import QtQuick

QtObject {
  readonly property var hostPresentation: typeof runtime !== "undefined"
    && runtime.presentation ? runtime.presentation : ({})
  readonly property int cornerRadius: 10
  readonly property int normalBorderWidth: 1
  readonly property int gapsOut: 16
  readonly property var spacing: ({xs: 6, sm: 10, md: 16, lg: 24, panelPadding: 24, controlPaddingY: 8, rowPaddingX: 12})
  readonly property var font: ({
    menuFamily: hostPresentation.fontFamily || "sans-serif",
    family: hostPresentation.fontFamily || "sans-serif",
    icon: 16,
    display: 28,
    displayLarge: 44,
    heading: 24,
    title: 20,
    body: 15,
    bodySmall: 13,
    caption: 12
  })
  readonly property var bar: ({
    size: hostPresentation.barSize || 26,
    iconSlot: hostPresentation.iconSlot || 27,
    statusSlot: hostPresentation.statusSlot || 21
  })

  function space(value) { return value }
  function hoverFillFor(foreground, accent) {
    return Qt.rgba(accent.r, accent.g, accent.b, 0.12)
  }
  function selectedFillFor(foreground, accent) {
    return Qt.rgba(accent.r, accent.g, accent.b, 0.20)
  }
}
