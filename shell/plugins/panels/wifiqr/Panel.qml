import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Centered Wi-Fi share overlay: no card, just the QR code floating on a
// heavy scrim. Esc or the scrim dismiss it.
//
// Standalone panel plugin: each summon regenerates the code via
// omarchy-network-qr, which emits the interface, security, and SSID it
// shared ahead of the module matrix — so a bare summon self-detects the
// connection. The payload may pin the interface and pre-title the card:
// {"iface": "wlan0", "ssid": "MyWifi"}.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string iface: ""
  property string ssid: ""
  property bool secured: false

  property var qrRows: []
  property int qrSize: 0
  property string error: ""
  property bool loading: false
  property bool expectedStop: false
  property bool pendingShow: false
  property string pendingIface: ""
  property string password: ""
  property bool passwordVisible: false
  property string passwordError: ""
  property bool pwExpectedStop: false

  readonly property bool showingQr: qrSize > 0 && !loading && error === ""

  // The scrim below is a fixed near-black regardless of theme, so text on
  // it needs a fixed light palette, not the themed foreground.
  readonly property color onScrim: "white"
  readonly property color onScrimDim: Qt.rgba(1, 1, 1, 0.55)
  readonly property color onScrimUrgent: "#ff6b6b"
  readonly property string fontFamily: Style.font.family

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    // The payload SSID titles the card during generation; the meta line the
    // generator emits is authoritative and overwrites it. A payload without
    // one clears the title: a re-summon may be sharing a different
    // connection, so the previous card's name must not label this one.
    root.ssid = payload.ssid !== undefined ? String(payload.ssid) : ""
    generate(String(payload.iface || ""))
    root.opened = true
    // The window is instantiated hidden, so the content's `focus: true` is
    // evaluated before the surface is mapped and Escape would land nowhere.
    // Re-acquire after mapping.
    Qt.callLater(function() {
      if (root.opened) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.pendingShow = false
    if (qrProc.running) {
      root.expectedStop = true
      qrProc.running = false
    }
    if (pwProc.running) pwProc.running = false
    root.qrSize = 0
    root.qrRows = []
    root.error = ""
    root.loading = false
    root.iface = ""
    root.ssid = ""
    root.secured = false
    // The Wi-Fi password only enters shell memory while the card is up.
    root.password = ""
    root.passwordVisible = false
    root.passwordError = ""
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.wifiqr")
    else close()
  }

  function generate(requestedIface) {
    if (qrProc.running) {
      // Whether the run in flight is a dismissal's SIGTERM still landing or
      // a live generation for an earlier summon, the latest request wins:
      // queue it for onExited and stop the old process.
      pendingShow = true
      pendingIface = requestedIface
      if (!expectedStop) {
        expectedStop = true
        qrProc.running = false
      }
      return
    }
    qrSize = 0
    qrRows = []
    error = ""
    loading = true
    expectedStop = false
    // A re-summon while the card is still loaded reaches here without a
    // close() in between, and may be sharing a different connection now:
    // neither the previous reveal's password nor a reveal still in flight
    // may survive onto the new card.
    iface = ""
    secured = false
    password = ""
    passwordVisible = false
    passwordError = ""
    if (pwProc.running) {
      pwExpectedStop = true
      pwProc.running = false
    }
    qrProc.command = requestedIface
      ? ["omarchy-network-qr", "--meta", requestedIface]
      : ["omarchy-network-qr", "--meta"]
    qrProc.running = true
  }

  function updateQr(raw) {
    var parsed = Model.parseQrOutput(raw)
    qrRows = parsed.matrix.rows
    qrSize = parsed.matrix.size
    if (parsed.meta.ssid !== "") ssid = parsed.meta.ssid
    if (parsed.meta.iface !== "") iface = parsed.meta.iface
    secured = parsed.meta.security !== "" && parsed.meta.security !== "nopass"
    // Good output settles the run: a canceled predecessor's stderr may have
    // landed after this generation started, and must not shadow its result.
    if (qrSize > 0) error = ""
  }

  function togglePassword() {
    if (passwordVisible) { passwordVisible = false; return }
    if (password !== "") { passwordVisible = true; return }
    if (pwProc.running || !iface) return
    passwordError = ""
    // Only a deliberate new lookup lowers the canceled-fetch guard, right as
    // it launches -- see the pwProc comment.
    pwExpectedStop = false
    pwProc.command = ["omarchy-network-password", iface]
    pwProc.running = true
  }

  Process {
    id: qrProc
    // Both collectors check expectedStop: a dismissal mid-generation kills
    // the process, but buffered output still arrives afterwards and would
    // repopulate qrSize -- reopening the card the user just closed. The flag
    // stays set through onExited (generate resets it) because the exit and
    // stream-finished signals have no guaranteed order.
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedStop) root.updateQr(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (!root.expectedStop) root.error = String(text || "").trim()
    }
    onExited: function(exitCode) {
      root.loading = false
      if (root.pendingShow) {
        root.pendingShow = false
        // expectedStop stays set until generate() launches the replacement:
        // the canceled run's collectors may fire between here and then, and
        // must keep being dropped.
        Qt.callLater(function() { root.generate(root.pendingIface) })
        return
      }
      if (root.expectedStop) return
      if (exitCode !== 0 || root.qrSize === 0) {
        root.qrSize = 0
        root.qrRows = []
        if (root.error === "") root.error = "Could not generate the Wi-Fi QR code"
      }
    }
  }

  // The Wi-Fi password only enters shell memory when the user clicks to
  // reveal it, and close() drops it again. Both handlers bail when the card
  // is gone so a fetch that was in flight during dismissal can't stash the
  // secret into a closed panel's state, and check pwExpectedStop so a fetch
  // that a regeneration killed can't reveal the previous network's password
  // under the new card. The exit and stream-finished signals have no
  // guaranteed order, so the flag survives onExited; only togglePassword
  // lowers it, as it launches the next deliberate lookup.
  Process {
    id: pwProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (root.opened && !root.pwExpectedStop) root.password = String(text || "").trim()
    }
    onExited: function(exitCode) {
      if (root.pwExpectedStop) return
      if (!root.opened) return
      if (exitCode === 0 && root.password !== "") root.passwordVisible = true
      else root.passwordError = "Could not read the Wi-Fi password"
    }
  }

  PanelWindow {
    visible: root.opened
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
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.dismiss()

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
            textFormat: Text.PlainText
            text: (root.ssid || "Wi-Fi").toUpperCase()
            color: root.onScrimDim
            font.family: root.fontFamily
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
            color: root.onScrimDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            textFormat: Text.PlainText
            visible: root.error !== ""
            text: root.error
            color: root.onScrimUrgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.maximumWidth: Style.space(320)
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            visible: root.showingQr
            text: "Scan to join this network"
            color: root.onScrimDim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            textFormat: Text.PlainText
            visible: root.showingQr && root.secured
            text: root.passwordError !== "" ? root.passwordError
              : root.passwordVisible ? root.password
              : "Show password"
            color: root.passwordError !== "" ? root.onScrimUrgent : root.onScrim
            opacity: root.passwordVisible || root.passwordError !== "" ? 1 : 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WrapAnywhere
            Layout.fillWidth: true
            Layout.maximumWidth: Style.space(320)
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePassword()
            }
          }
        }
      }
    }
  }
}
