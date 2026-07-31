import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  required property var qrRows
  required property int qrSize
  required property bool loading
  required property string error
  required property string ssid
  required property bool secured
  required property string password
  required property bool passwordVisible
  required property string passwordError
  property bool open: false

  readonly property bool showingQr: qrSize > 0 && !loading && error === ""

  signal closeRequested()
  signal passwordToggleRequested()

  visible: open
  // The window is instantiated hidden, so the content's `focus: true` is
  // evaluated before the surface is mapped and Escape would land nowhere.
  // Re-acquire after mapping, as KeyboardPanel does.
  onOpenChanged: {
    if (open) Qt.callLater(function() {
      if (root.open) keyCatcher.forceActiveFocus()
    })
  }
  screen: anchorItem.QsWindow.window ? anchorItem.QsWindow.window.screen : null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-network-qr"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  BorderSurface {
    width: Style.space(320)
    height: content.implicitHeight + Style.space(48)
    anchors.centerIn: parent
    radius: Style.cornerRadius
    color: Color.menu.background
    borderSpec: Border.surfaceSpec("menu", "border", Color.popups.border, Math.max(1, Style.space(2)))

    MouseArea { anchors.fill: parent; onClicked: {} }

    Item {
      id: keyCatcher
      anchors.fill: parent
      anchors.margins: Style.space(24)
      focus: true

      Keys.onEscapePressed: root.closeRequested()

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(12)

        Text {
          text: "Share " + (root.ssid || "Wi-Fi")
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        // Render every QR module as an integer-sized native rectangle. This
        // stays crisp and avoids temporary images and file-cache races.
        Rectangle {
          id: qrCanvas
          readonly property int moduleSize: root.qrSize > 0
            ? Math.max(4, Math.floor(Style.space(240) / root.qrSize))
            : 0

          visible: root.showingQr
          width: root.qrSize * moduleSize
          height: width
          color: "white"
          Layout.alignment: Qt.AlignHCenter

          Grid {
            anchors.fill: parent
            columns: root.qrSize

            Repeater {
              model: root.qrSize * root.qrSize

              Rectangle {
                required property int index
                readonly property int matrixRow: Math.floor(index / root.qrSize)
                readonly property int matrixColumn: index % root.qrSize

                width: qrCanvas.moduleSize
                height: qrCanvas.moduleSize
                color: root.qrRows[matrixRow].charAt(matrixColumn) === "1" ? "#111111" : "white"
              }
            }
          }
        }

        Text {
          visible: root.loading
          text: "Generating QR code…"
          color: root.bar.foreground
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.error !== ""
          text: root.error
          color: root.bar.urgent
          wrapMode: Text.Wrap
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.showingQr
          text: "Scan to join this network"
          color: root.bar.foreground
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.showingQr && root.secured
          text: root.passwordError !== "" ? root.passwordError
            : root.passwordVisible ? root.password
            : "Show password"
          color: root.passwordError !== "" ? root.bar.urgent : root.bar.foreground
          opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WrapAnywhere
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.passwordToggleRequested()
          }
        }
      }
    }
  }
}
