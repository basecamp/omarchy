import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BorderSurface {
  id: root

  required property int workspaceId
  property var workspace: null
  property bool focused: false
  property bool addWorkspace: false
  property bool keyboardSelected: false
  property var draggedToplevel: null

  readonly property var toplevelModel: workspace ? workspace.toplevels : []
  readonly property int windowCount: workspace ? workspace.toplevels.values.length : 0
  readonly property bool occupied: windowCount > 0
  readonly property int previewColumns: windowCount === 2 ? 2 : Math.max(1, Math.ceil(Math.sqrt(windowCount)))
  readonly property int previewRows: Math.max(1, Math.ceil(windowCount / previewColumns))
  readonly property real headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property real previewSpacing: Style.spacing.sm
  readonly property int draggedSourceWorkspaceId: draggedToplevel && draggedToplevel.workspace
    ? Number(draggedToplevel.workspace.id) : -1
  readonly property bool validDropTarget: draggedToplevel !== null
    && String(draggedToplevel.address || "") !== ""
    && workspaceId > 0 && workspaceId <= 10
    && draggedSourceWorkspaceId !== workspaceId
  readonly property bool dropHovered: validDropTarget && dropArea.containsDrag
  readonly property var normalBorderSpec: keyboardSelected
    ? Border.withWidth(Border.controlSpec("focus", Color.menu.text, Color.accent), Math.max(Style.space(2), Style.focusBorderWidth))
    : (focused
      ? Border.hyprlandActiveSpec(Color.accent, Math.max(1, Style.normalBorderWidth))
      : (occupied
        ? Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.normalBorderWidth))
        : Border.flat(Util.alpha(Color.menu.border, 0.28), Math.max(1, Style.normalBorderWidth))))

  signal workspaceActivated()
  signal windowActivated(var toplevel)
  signal windowDragStarted(var toplevel)
  signal windowDragFinished(var toplevel)
  signal windowDropped(var toplevel)

  radius: Style.cornerRadius
  color: occupied ? Color.menu.background : Util.alpha(Color.menu.background, 0.72)
  borderSpec: dropHovered
    ? Border.withWidth(Border.controlSpec("focus", Color.menu.text, Color.accent), Math.max(Style.space(2), Style.focusBorderWidth))
    : (validDropTarget
      ? Border.withWidth(Border.controlSpec("hover-cursor", Color.menu.text, Color.accent), Math.max(1, Style.hoverBorderWidth))
      : normalBorderSpec)
  clip: true

  MouseArea {
    anchors.fill: parent
    z: 1
    cursorShape: Qt.PointingHandCursor
    onClicked: root.workspaceActivated()
  }

  Rectangle {
    anchors.fill: parent
    z: 2
    color: root.dropHovered
      ? Style.selectedFillFor(Color.menu.text, Color.accent)
      : (root.validDropTarget || root.keyboardSelected
        ? Style.hoverFillFor(Color.menu.text, Color.accent) : "transparent")

    Behavior on color {
      ColorAnimation { duration: 60 }
    }
  }

  Text {
    id: workspaceLabel
    visible: !root.addWorkspace
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    height: root.headerHeight
    text: root.workspaceId === 10 ? "Workspace 0" : "Workspace " + root.workspaceId
    color: root.focused ? Color.accent : Color.menu.text
    opacity: root.occupied || root.focused ? 1 : 0.58
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.title
    font.bold: root.focused
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
  }

  Text {
    visible: !root.occupied && !root.addWorkspace
    anchors.centerIn: previewArea
    text: "Empty"
    color: Color.menu.text
    opacity: 0.42
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
  }

  Item {
    id: previewArea
    visible: !root.addWorkspace
    z: 5
    anchors.top: workspaceLabel.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.spacing.md

    Grid {
      anchors.fill: parent
      columns: root.previewColumns
      spacing: root.previewSpacing

      Repeater {
        model: root.toplevelModel

        WindowPreview {
          required property var modelData

          width: Math.max(1, (previewArea.width - root.previewSpacing * (root.previewColumns - 1)) / root.previewColumns)
          height: Math.max(1, (previewArea.height - root.previewSpacing * (root.previewRows - 1)) / root.previewRows)
          toplevel: modelData
          onActivated: root.windowActivated(modelData)
          onDragStarted: root.windowDragStarted(modelData)
          onDragFinished: root.windowDragFinished(modelData)
        }
      }
    }
  }

  Text {
    visible: root.addWorkspace
    anchors.centerIn: parent
    z: 3
    text: "+"
    color: Color.menu.text
    opacity: root.dropHovered ? 1 : 0.58
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.displayLarge
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }

  DropArea {
    id: dropArea
    anchors.fill: parent
    z: 20
    keys: ["omarchy-window"]
    enabled: root.validDropTarget

    onDropped: function(drop) {
      if (!root.validDropTarget || !drop.source || !drop.source.toplevel) {
        drop.accepted = false
        return
      }
      drop.acceptProposedAction()
      root.windowDropped(drop.source.toplevel)
    }
  }
}
