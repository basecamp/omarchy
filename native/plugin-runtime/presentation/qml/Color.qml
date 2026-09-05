pragma Singleton
import QtQuick

QtObject {
  readonly property var hostPresentation: typeof pluginPresentation !== "undefined"
    ? pluginPresentation : ({})
  readonly property color foreground: hostPresentation.foreground || "#f2f4f8"
  readonly property color background: hostPresentation.background || "#090a0c"
  readonly property color accent: hostPresentation.accent || "#5e81ac"
  readonly property color urgent: hostPresentation.urgent || "#bf616a"
  readonly property var bar: ({
    background: hostPresentation.barBackground || background,
    text: hostPresentation.barForeground || foreground,
    active: urgent
  })
  readonly property var menu: ({background: background, text: foreground, border: accent})
  readonly property var popups: ({background: background, text: foreground})

  function alpha(value, opacity) {
    return Qt.rgba(value.r, value.g, value.b, opacity)
  }
}
