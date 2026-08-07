import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property bool opened: false
  property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  property var draggedToplevel: null
  property int selectedCardIndex: -1

  readonly property var workspaceModel: root.workspaceIds()
  readonly property int workspaceCount: workspaceModel.length
  readonly property int nextWorkspaceId: root.nextWorkspaceAfter(workspaceModel)
  readonly property var overviewCardModel: {
    var ids = workspaceModel.slice()
    if (nextWorkspaceId > 0) ids.push(nextWorkspaceId)
    return ids
  }
  readonly property int cardCount: overviewCardModel.length
  readonly property real cardAspectRatio: 1.55
  readonly property real outerMargin: Math.max(Style.gapsOut, Style.spacing.panelPadding)
  readonly property real gridSpacing: Style.spacing.lg
  readonly property real availableWidth: Math.max(1, panel.width - outerMargin * 2)
  readonly property real availableHeight: Math.max(1, panel.height - outerMargin * 2)
  readonly property int columns: Math.max(1, Math.min(cardCount,
    Math.ceil(Math.sqrt(cardCount * availableWidth / availableHeight / cardAspectRatio))))
  readonly property int rows: Math.max(1, Math.ceil(cardCount / columns))
  readonly property real cardWidth: Math.max(1, Math.min(
    Style.space(520),
    (availableWidth - gridSpacing * (columns - 1)) / columns,
    ((availableHeight - gridSpacing * (rows - 1)) / rows) * cardAspectRatio))
  readonly property real cardHeight: Math.max(1, cardWidth / cardAspectRatio)

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function nextWorkspaceAfter(ids) {
    if (!ids || ids.length === 0) return -1
    var next = ids[ids.length - 1] + 1
    return next <= 10 ? next : -1
  }

  function cardIndexAfterMove(index, dx, dy, count, columnCount) {
    if (count <= 0) return -1
    var current = Math.max(0, Math.min(index, count - 1))
    var cols = Math.max(1, columnCount)
    var row = Math.floor(current / cols)
    var column = current % cols

    if (dx < 0) return Math.max(row * cols, current - 1)
    if (dx > 0) return Math.min(Math.min(row * cols + cols - 1, count - 1), current + 1)

    var targetRow = Math.max(0, Math.min(Math.ceil(count / cols) - 1, row + dy))
    return Math.min(targetRow * cols + column, count - 1)
  }

  function initialSelectedCardIndex() {
    var focused = Hyprland.focusedWorkspace
    if (focused) {
      var index = root.workspaceModel.indexOf(focused.id)
      if (index >= 0) return index
    }
    return root.cardCount > 0 ? 0 : -1
  }

  function moveCardSelection(dx, dy) {
    root.selectedCardIndex = root.cardIndexAfterMove(
      root.selectedCardIndex, dx, dy, root.cardCount, root.columns)
  }

  function activateSelectedCard() {
    var index = root.selectedCardIndex
    if (index < 0 || index >= root.cardCount) return
    var workspaceId = root.overviewCardModel[index]
    if (root.nextWorkspaceId > 0 && index === root.workspaceCount)
      root.activateNextWorkspace()
    else
      root.activateWorkspace(root.workspaceById(workspaceId), workspaceId)
  }

  function normalizedAddress(toplevel) {
    var address = String((toplevel && toplevel.address) || "").trim()
    if (!address.match(/^(0x)?[0-9a-fA-F]+$/)) return ""
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function sourceWorkspaceId(toplevel) {
    return toplevel && toplevel.workspace ? Number(toplevel.workspace.id) : -1
  }

  function dispatchWorkspace(workspaceId) {
    if (workspaceId <= 0 || workspaceId > 10) return false
    if (Hyprland.usingLua)
      Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + workspaceId + "\" })")
    else
      Hyprland.dispatch("workspace " + workspaceId)
    return true
  }

  function focusedScreen() {
    var monitor = Hyprland.focusedMonitor
    var screens = Quickshell.screens || []
    if (monitor) {
      for (var i = 0; i < screens.length; i++) {
        if (screens[i] && screens[i].name === monitor.name) return screens[i]
      }
    }
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    root.targetScreen = root.focusedScreen()
    root.draggedToplevel = null
    root.selectedCardIndex = root.initialSelectedCardIndex()
    root.opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.draggedToplevel = null
    root.selectedCardIndex = -1
    root.opened = false
  }

  function dismiss() {
    root.draggedToplevel = null
    root.selectedCardIndex = -1
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.workspace-overview")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function activateWorkspace(workspace, workspaceId) {
    if (workspace) workspace.activate()
    else if (!root.dispatchWorkspace(workspaceId)) return
    Qt.callLater(root.dismiss)
  }

  function activateNextWorkspace() {
    var workspaceId = root.nextWorkspaceId
    if (!root.dispatchWorkspace(workspaceId)) return
    Qt.callLater(root.dismiss)
  }

  function activateWindow(toplevel) {
    var address = root.normalizedAddress(toplevel)
    var wayland = toplevel ? toplevel.wayland : null
    if (address && Hyprland.usingLua)
      Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })")
    else if (address)
      Hyprland.dispatch("focuswindow address:" + address)
    else if (wayland)
      wayland.activate()
    else
      return
    Qt.callLater(root.dismiss)
  }

  function moveWindowToWorkspace(toplevel, workspaceId) {
    var address = root.normalizedAddress(toplevel)
    var sourceId = root.sourceWorkspaceId(toplevel)
    if (!address || workspaceId <= 0 || workspaceId > 10 || sourceId === workspaceId) return false

    root.draggedToplevel = null
    if (Hyprland.usingLua) {
      Hyprland.dispatch("hl.dsp.window.move({ workspace = \"" + workspaceId
        + "\", window = \"address:" + address + "\", follow = false })")
    } else {
      Hyprland.dispatch("movetoworkspacesilent " + workspaceId + ",address:" + address)
    }
    return true
  }

  function beginWindowDrag(toplevel) {
    if (root.normalizedAddress(toplevel)) root.draggedToplevel = toplevel
  }

  function endWindowDrag(toplevel) {
    if (root.draggedToplevel === toplevel) root.draggedToplevel = null
  }

  PanelWindow {
    id: panel

    screen: root.targetScreen
    visible: root.opened && root.targetScreen !== null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-workspace-overview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCardSelection(dx, dy) }
      onActivateRequested: root.activateSelectedCard()
      onCloseRequested: root.dismiss()

      Grid {
        id: workspaceGrid
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        columns: root.columns
        spacing: root.gridSpacing

        Repeater {
          model: root.overviewCardModel

          WorkspaceCard {
            required property int modelData
            required property int index

            readonly property bool isAddCard: root.nextWorkspaceId > 0
              && index === root.workspaceCount

            width: root.cardWidth
            height: root.cardHeight
            workspaceId: modelData
            workspace: isAddCard ? null : root.workspaceById(modelData)
            addWorkspace: isAddCard
            draggedToplevel: root.draggedToplevel
            keyboardSelected: index === root.selectedCardIndex
            focused: !isAddCard && Hyprland.focusedWorkspace !== null
              && Hyprland.focusedWorkspace.id === modelData
            onWorkspaceActivated: {
              if (isAddCard) root.activateNextWorkspace()
              else root.activateWorkspace(workspace, modelData)
            }
            onWindowActivated: function(toplevel) { root.activateWindow(toplevel) }
            onWindowDragStarted: function(toplevel) { root.beginWindowDrag(toplevel) }
            onWindowDragFinished: function(toplevel) { root.endWindowDrag(toplevel) }
            onWindowDropped: function(toplevel) { root.moveWindowToWorkspace(toplevel, modelData) }
          }
        }
      }
    }
  }

  Connections {
    target: root.draggedToplevel
    ignoreUnknownSignals: true
    function onDestroyed() { root.draggedToplevel = null }
  }

  onCardCountChanged: {
    if (root.selectedCardIndex >= root.cardCount)
      root.selectedCardIndex = root.cardCount - 1
  }
}
