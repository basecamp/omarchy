import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Visual reference + live playground for omarchy-shell's common UI
// components. Summoned via:
//   omarchy-shell-ipc shell summon omarchy.dev-gallery "{}"
//
// Every section here renders the REAL component (not a copy) so the
// gallery doubles as a smoke test. When you add a new common component,
// add a section here. Maintenance discipline: this file should ONLY use
// imported common components, never inline reimplementations of them.
Item {
  id: root

  // ---- plugin lifecycle ---------------------------------------------------
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    Qt.callLater(function() { if (focusSink) focusSink.forceActiveFocus() })
  }

  // Host-initiated close (`shell hide`). Visibility flips without
  // notifying the host back — it already knows.
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close (Esc, window close button). Tell the shell so its
  // openPanelIds map stays consistent and `toggle` works on the next call.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("omarchy.dev-gallery")
    else window.visible = false
  }

  // ---- host injections ----------------------------------------------------
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var shell: null
  property var manifest: null

  // ---- theme --------------------------------------------------------------
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: "monospace"

  // Fake `bar` for components that take a whole bar object (e.g. Slider).
  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: root.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  // ---- cursor demo state --------------------------------------------------
  property int cursorDemoIndex: 1

  FloatingWindow {
    id: window
    title: "Omarchy shell – dev gallery"
    color: root.background
    implicitWidth: 720
    implicitHeight: 760
    minimumSize: Qt.size(560, 520)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("omarchy.dev-gallery")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      Item {
        id: focusSink
        width: 1; height: 1
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
          if (event.key === Qt.Key_Right || event.text === "l") {
            root.cursorDemoIndex = Math.min(2, root.cursorDemoIndex + 1)
            event.accepted = true
          }
          if (event.key === Qt.Key_Left || event.text === "h") {
            root.cursorDemoIndex = Math.max(0, root.cursorDemoIndex - 1)
            event.accepted = true
          }
        }
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        anchors.margins: 18
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: scrollArea.availableWidth
          spacing: 22

          // ---- Header ------------------------------------------------------
          Column {
            width: parent.width
            spacing: 4

            Text {
              text: "Omarchy shell · dev gallery"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 18
              font.bold: true
            }
            Text {
              text: "Live previews of every type exported from qs.Ui. Use this as the visual reference when porting panels or building plugins. Press h/l to walk the cursor demo, Esc to close."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: 11
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- PanelSectionHeader ------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelSectionHeader"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Small-caps-style intro label for a section."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
            }

            Rectangle {
              width: parent.width
              implicitHeight: shCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: shCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                PanelSectionHeader {
                  text: "DNS provider"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                PanelSectionHeader {
                  text: "Wi-Fi networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                PanelSectionHeader {
                  text: "Playing"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: 11
                }
              }
            }
          }

          // ---- PanelSeparator ----------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelSeparator"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "1px horizontal rule. Default 0.12 alpha on foreground; tweak via strength."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
            }

            Rectangle {
              width: parent.width
              implicitHeight: sepCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: sepCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                PanelSeparator { foreground: root.foreground }
                PanelSeparator { foreground: root.foreground; strength: 0.25 }
                PanelSeparator { foreground: root.foreground; strength: 0.45 }
              }
            }
          }

          // ---- CursorSurface -----------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "CursorSurface"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Single highlight chrome for keyboard+mouse navigable items. Press h/l (anywhere in this window) to move the demo cursor. The middle item is also marked `current` to show how the two states layer."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: csCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: csCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                Repeater {
                  model: [
                    { "label": "Idle row" },
                    { "label": "Currently-active row (e.g. connected wifi, default sink)" },
                    { "label": "Forget / scan / disabled-ish row" }
                  ]

                  CursorSurface {
                    required property var modelData
                    required property int index
                    width: parent.width
                    implicitHeight: csLabel.implicitHeight + 16
                    hasCursor: root.cursorDemoIndex === index
                    current: index === 1
                    foreground: root.foreground
                    fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                    Text {
                      id: csLabel
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 10
                      anchors.rightMargin: 10
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onContainsMouseChanged: if (containsMouse) root.cursorDemoIndex = parent.index
                    }
                  }
                }
              }
            }
          }

          // ---- PillButton --------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PillButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Compact rounded button with optional icon, label, tooltip, and `active` highlight. Used inside panels for inline actions (Refresh, DNS pills, Bluetooth header)."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: pillCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: pillCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 6

                PillButton {
                  text: "DHCP"
                  tooltipText: "Use DNS from DHCP"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                PillButton {
                  text: "Cloudflare"
                  tooltipText: "Set DNS to Cloudflare"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: true
                }

                PillButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: 8
                  verticalPadding: 4
                }

                PillButton {
                  iconText: "󰂯"
                  text: "On"
                  tooltipText: "Turn Bluetooth off"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: true
                }
              }
            }
          }

          // ---- PanelActionButton -------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelActionButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "22×22 right-edge action button. Two flavors via hoverColor: default (foreground tint, e.g. confirm) and urgent (red tint, e.g. forget/unpair). Hover and click states are intrinsic; the row that owns it stays responsible for the cursor highlight."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: pabCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: pabCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 18

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Confirm (default flavor)"
                  foreground: root.foreground
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                }

                PanelActionButton {
                  iconText: "󰅙"
                  tooltipText: "Forget network (urgent flavor)"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                }

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Disabled — type a passphrase first"
                  foreground: root.foreground
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                  enabled: false
                }
              }
            }
          }

          // ---- PanelToolTip ------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelToolTip"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Hover the swatch below to see the styled tooltip. Use this whenever a custom button or row needs a hover hint."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: 140
              height: 36
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
              border.width: 1
              radius: 4

              Text {
                anchors.centerIn: parent
                text: "hover me"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 12
              }

              MouseArea {
                id: tipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
              }

              PanelToolTip {
                visible: tipMouse.containsMouse
                text: "Styled tooltip — drop into any panel"
                panelForeground: root.foreground
                panelBackground: root.background
                fontFamily: root.fontFamily
              }
            }
          }


          // ---- Slider ------------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Slider"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Volume / progress slider. Drag, click anywhere on the track, or scroll the wheel."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: sliderRow.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: sliderRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                property real demoVolume: 0.45

                Text {
                  text: "󰕾"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 16
                  width: 22
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                PanelSlider {
                  id: demoSlider
                  bar: root.fakeBar
                  width: parent.width - 70
                  anchors.verticalCenter: parent.verticalCenter
                  value: sliderRow.demoVolume
                  onMoved: function(v) { sliderRow.demoVolume = v }
                }

                Text {
                  text: Math.round((demoSlider.dragging ? demoSlider.liveValue : sliderRow.demoVolume) * 100) + "%"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  width: 38
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // ---- Composed example -------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Composed example"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "A miniature wifi-style row built from CursorSurface + PanelActionButton + PanelToolTip. This is what new panel rows should look like — no inline Rectangle/Text/MouseArea reimplementation."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: composedCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: 6
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: composedCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                PanelSectionHeader {
                  text: "Wi-Fi networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                CursorSurface {
                  width: parent.width
                  implicitHeight: composedRow.implicitHeight + 12
                  current: true
                  foreground: root.foreground
                  fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                  Item {
                    id: composedRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    implicitHeight: 36

                    Text {
                      id: composedIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    PanelActionButton {
                      id: composedForget
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰅙"
                      tooltipText: "Forget network"
                      foreground: root.foreground
                      hoverColor: root.urgent
                      panelBackground: root.background
                      fontFamily: root.fontFamily
                    }

                    Column {
                      spacing: 1
                      anchors.left: composedIcon.right
                      anchors.leftMargin: 10
                      anchors.right: composedForget.left
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        text: "HughesWiFi"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: parent.width
                      }
                      Text {
                        text: "Connected"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }
                  }
                }

                PanelSeparator { foreground: root.foreground }

                CursorSurface {
                  width: parent.width
                  implicitHeight: idleRow.implicitHeight + 12
                  foreground: root.foreground
                  fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

                  Item {
                    id: idleRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    implicitHeight: 36

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: 24
                      anchors.verticalCenter: parent.verticalCenter
                      text: "HughesATT"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 12
                    }
                  }
                }
              }
            }
          }

          Item { width: 1; height: 12 }
        }
      }
    }
  }
}
