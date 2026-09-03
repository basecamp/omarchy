pragma Singleton
import QtQuick

QtObject {
  readonly property color foreground: "#f2f4f8"
  readonly property color background: "#090a0c"
  readonly property color accent: "#5e81ac"
  readonly property color urgent: "#bf616a"
  readonly property var menu: ({background: background, text: foreground, border: "#3b4252"})
  readonly property var popups: ({background: "#111820"})

  function alpha(value, opacity) {
    return Qt.rgba(value.r, value.g, value.b, opacity)
  }
}
