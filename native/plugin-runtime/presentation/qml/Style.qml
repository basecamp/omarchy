pragma Singleton
import QtQuick
QtObject {
  readonly property QtObject font: QtObject { readonly property string family: "sans-serif"; readonly property int body: 15; readonly property int bodySmall: 13; readonly property int caption: 12; readonly property int displayLarge: 44; readonly property int icon: 16 }
  readonly property QtObject spacing: QtObject { readonly property int rowPaddingX: 12 }
  readonly property QtObject bar: QtObject { readonly property int iconCanvas: 24 }
  function space(value) { return value }
}
