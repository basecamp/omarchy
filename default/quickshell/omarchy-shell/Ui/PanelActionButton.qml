import QtQuick

// Small (22×22 by default) icon button used at the right edge of panel rows
// for inline actions — forget network, confirm passphrase, unpair device,
// etc. Two visual modes are supported via `hoverColor`:
//   - default: hoverColor === foreground → subtle foreground-tint hover
//   - urgent:  hoverColor === bar.urgent → red-tint hover for destructive
//              actions like forget/unpair
//
// `enabled` gates clicks and dims the icon. The component owns its own
// hover state visuals; mouse hover does NOT update any panel cursor state
// here because action buttons are not cursor targets — the row they live
// in is.
Rectangle {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: "#cacccc"
  property color hoverColor: foreground
  property color panelBackground: "#101315"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property real fontSize: 14
  property real size: 22

  signal clicked()

  implicitWidth: size
  implicitHeight: size
  radius: 4

  color: mouse.containsMouse && root.enabled
    ? Qt.rgba(hoverColor.r, hoverColor.g, hoverColor.b, 0.20)
    : "transparent"

  Behavior on color { ColorAnimation { duration: 60 } }

  Text {
    anchors.centerIn: parent
    text: root.iconText
    color: root.enabled
      ? (mouse.containsMouse ? root.hoverColor : Qt.darker(root.foreground, 1.3))
      : Qt.darker(root.foreground, 2.0)
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onClicked: root.clicked()
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    panelForeground: root.foreground
    panelBackground: root.panelBackground
    fontFamily: root.fontFamily
  }
}
