pragma Singleton
import QtQuick
QtObject {
  readonly property QtObject font: QtObject { readonly property string family: "sans-serif" }
  readonly property int spacing: 8
  function space(value) { return value }
}
