import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Centered Wi-Fi share overlay, presented like the speed test: no card,
// just the QR code floating on a heavy scrim. Esc or the scrim dismiss it.
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

  // Deep scrim: the floating code needs the backdrop to carry the contrast
  // on any wallpaper.
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.78)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    focus: true

    Keys.onEscapePressed: root.closeRequested()

    Item {
      anchors.centerIn: parent
      width: content.implicitWidth
      height: content.implicitHeight
      // Narrow or heavily scaled outputs: shrink the whole card rather than
      // clipping it at the screen edge.
      scale: Math.min(1,
        (keyCatcher.width - Style.space(32)) / Math.max(1, width),
        (keyCatcher.height - Style.space(32)) / Math.max(1, height))

      // Swallow clicks so only the scrim outside the content dismisses.
      MouseArea { anchors.fill: parent; onClicked: {} }

      ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Style.space(16)

        Text {
          text: (root.ssid || "Wi-Fi").toUpperCase()
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 2
          elide: Text.ElideRight
          Layout.maximumWidth: Style.space(320)
          Layout.alignment: Qt.AlignHCenter
          horizontalAlignment: Text.AlignHCenter
        }

        // Render every QR module as an integer-sized native rectangle. This
        // stays crisp and avoids temporary images and file-cache races. Only
        // the dark modules paint, so the white canvas can keep its rounded
        // corners; the spec quiet zone baked into the matrix keeps the code
        // itself clear of them.
        Rectangle {
          id: qrCanvas
          readonly property int moduleSize: root.qrSize > 0
            ? Math.max(4, Math.floor(Style.space(240) / root.qrSize))
            : 0

          visible: root.showingQr
          width: root.qrSize * moduleSize
          height: width
          color: "white"
          radius: Style.cornerRadius
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
                color: root.qrRows[matrixRow].charAt(matrixColumn) === "1" ? "#111111" : "transparent"
              }
            }
          }
        }

        Text {
          visible: root.loading
          text: "Generating QR code…"
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.error !== ""
          text: root.error
          color: root.bar.urgent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(320)
          horizontalAlignment: Text.AlignHCenter
        }

        Text {
          visible: root.showingQr
          text: "Scan to join this network"
          color: Qt.darker(root.bar.foreground, 1.3)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
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
          Layout.maximumWidth: Style.space(320)
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
