import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Local AI: one bar icon plus a popup for the model server. The popup is
// deliberately small — the serving state and the validated catalog modes.
// Everything else (sync, logs, removal) lives in the omarchy-ai-* commands.
Panel {
  id: root
  moduleName: "omarchy.local-ai"
  ipcTarget: "omarchy.local-ai"
  manageIpc: false

  property var info: ({})
  property int recipeIndex: 0
  property bool cursorActive: false

  readonly property var recipes: info.recipes instanceof Array ? info.recipes : []
  readonly property bool installed: !!info.state && info.state !== "not-setup"
  readonly property bool serving: info.state === "ready"
  readonly property bool loaded: serving || info.state === "loading"
  readonly property color dim: bar ? Qt.darker(bar.foreground, 1.55) : Color.foreground
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string activeLabel: {
    for (var i = 0; i < recipes.length; i++)
      if (recipes[i].active) return recipes[i].label
    return String(info.active || "")
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function toggleServer() {
    if (!toggleProc.running) toggleProc.running = true
  }

  function switchTo(recipe) {
    if (!recipe || !recipe.fits) return
    if (recipe.active) {
      // Selecting the model that is already set up loads it when stopped.
      if (!loaded) toggleServer()
      return
    }
    if (bar) bar.run("omarchy-launch-floating-terminal-with-presentation " + Util.shellQuote("omarchy-ai-setup " + recipe.name))
    close()
  }

  function activeIndex() {
    for (var i = 0; i < recipes.length; i++)
      if (recipes[i].active) return i
    return 0
  }

  function selectByDelta(delta) {
    if (recipes.length === 0) return
    recipeIndex = Math.max(0, Math.min(recipes.length - 1, recipeIndex + delta))
  }

  visible: installed
  implicitWidth: installed ? button.implicitWidth : 0
  implicitHeight: installed ? button.implicitHeight : 0

  onOpenedChanged: {
    if (opened) {
      refresh()
      recipeIndex = activeIndex()
      cursorActive = false
    }
  }

  IpcHandler {
    target: "omarchy.local-ai"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  Process {
    id: listProc
    command: ["omarchy-ai-list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.info = JSON.parse(text) } catch (e) { root.info = {} }
      }
    }
  }

  Process {
    id: toggleProc
    command: ["omarchy-ai-toggle"]
    onExited: root.refresh()
  }

  Timer { interval: 30000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰚩"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    opacity: root.serving ? 1 : root.loaded ? 0.75 : 0.5
    tooltipText: root.serving ? "Local AI: serving " + String(root.info.active || "") + " — right-click to unload"
                              : root.loaded ? "Local AI: loading " + String(root.info.active || "") + " — right-click to unload"
                                            : "Local AI: stopped — right-click to load"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleServer()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.selectByDelta(dy)
        else if (dx !== 0) root.selectByDelta(dx)
      }
      onActivateRequested: if (root.cursorActive) root.switchTo(root.recipes[root.recipeIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: state + load/unload ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroLabels.implicitHeight, heroToggle.implicitHeight)

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: heroToggle.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Local AI"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: (root.serving ? "SERVING · " + root.activeLabel : root.loaded ? "LOADING · " + root.activeLabel : "UNLOADED").toUpperCase()
              color: root.loaded ? root.bar.foreground : root.dim
              opacity: root.loaded ? 0.75 : 1
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Button {
            id: heroToggle
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.loaded ? "Unload" : "Load"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            horizontalPadding: Style.spacing.controlPaddingX
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: root.loaded
            onClicked: root.toggleServer()
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Catalog modes ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.recipes

            Rectangle {
              id: recipeRow

              required property var modelData
              required property int index

              readonly property bool usable: modelData.fits === true && modelData.active !== true

              width: parent.width
              implicitHeight: rowContent.implicitHeight + Style.space(12)
              radius: Style.cornerRadius
              color: root.cursorActive && root.recipeIndex === index ? root.hoverFill : "transparent"
              opacity: modelData.fits ? 1 : 0.45

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: recipeRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                  root.cursorActive = true
                  root.recipeIndex = recipeRow.index
                }
                onClicked: root.switchTo(recipeRow.modelData)
              }

              Row {
                id: rowContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  id: rowMark
                  text: recipeRow.modelData.active ? "●" : "○"
                  color: recipeRow.modelData.active ? root.bar.foreground : root.dim
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  width: parent.width - rowMark.implicitWidth - parent.spacing
                  text: recipeRow.modelData.label
                  color: root.bar.foreground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }
        }
      }
    }
  }
}
