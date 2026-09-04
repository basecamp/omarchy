import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.backup"
  ipcTarget: "omarchy.backup"
  manageIpc: false

  property string focusSection: "actions"
  property int actionIndex: 0
  property int snapshotIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string glyph: "󰁯"
  readonly property string problemText: backup.problem

  readonly property color barIconColor: backup.attention
    ? (bar ? bar.urgent : Color.urgent)
    : (backup.paused || !backup.configured ? Qt.darker(barForeground, 1.55) : barForeground)

  readonly property var actions: {
    if (!backup.configured) return [{id: "setup", glyph: "󰒓", label: "Set up backups", detail: "Encrypted, hourly, off-site"}]

    var rows = [{
      id: "now",
      glyph: "󰑓",
      label: backup.running ? "Backing up now" : "Back up now",
      detail: backup.running ? Model.progressText(backup.status) : "Send what has changed since the last run"
    }]

    if (backup.paused) {
      rows.push({id: "resume", glyph: "󰐊", label: "Resume backups", detail: Model.pauseText(backup.status, backup.nowMs)})
    } else {
      rows.push({id: "pause", glyph: "󰏤", label: "Pause for an hour", detail: "Scheduled runs wait until then"})
    }

    rows.push({id: "browse", glyph: "󰉋", label: "Browse older versions", detail: "Every backup as a dated folder"})
    return rows
  }

  function ensureCursor() {
    if (focusSection === "snapshots" && backup.snapshots.length === 0) focusSection = "actions"
    actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex))
    snapshotIndex = Math.max(0, Math.min(Math.max(0, backup.snapshots.length - 1), snapshotIndex))
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return

    if (focusSection === "actions") {
      if (dy > 0 && actionIndex === actions.length - 1 && backup.snapshots.length > 0) {
        focusSection = "snapshots"
        snapshotIndex = 0
        return
      }
      actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dy))
      return
    }

    if (dy < 0 && snapshotIndex === 0) {
      focusSection = "actions"
      actionIndex = actions.length - 1
      return
    }
    snapshotIndex = Math.max(0, Math.min(backup.snapshots.length - 1, snapshotIndex + dy))
  }

  function runAction(id) {
    switch (id) {
    case "setup": backup.setUp(); break
    case "now": backup.backUpNow(); break
    case "pause": backup.pause("1h"); break
    case "resume": backup.resume(); break
    case "browse": backup.browse(); break
    }
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "actions") runAction(actions[actionIndex].id)
    else backup.browse()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = "actions"
    actionIndex = 0
    backup.nowMs = Date.now()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: backup
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function run(): string { backup.backUpNow(); return "ok" }
    function status(): string { return backup.heroMeta }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: root.barIconColor
    dimmed: backup.paused && !backup.attention
    tooltipText: backup.heroMeta
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) backup.backUpNow()
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
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(key) {
        if (key === "b" || key === "B") backup.backUpNow()
        else if (key === "p" || key === "P") backup.paused ? backup.resume() : backup.pause("1h")
        else if (key === "o" || key === "O") backup.browse()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Backups"
            meta: backup.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: backup.paused ? 0.5 : 1.0
            iconComponent: Component {
              Text {
                text: root.glyph
                color: backup.attention ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item {
            visible: backup.running
            width: parent.width
            implicitHeight: Style.space(6)

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            }

            Rectangle {
              height: parent.height
              width: parent.width * Math.max(0, Math.min(100, backup.percent)) / 100
              radius: height / 2
              color: root.foreground
              Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutQuad } }
            }
          }

          Text {
            visible: root.problemText !== ""
            width: parent.width
            text: root.problemText
            color: backup.attention ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            visible: backup.configured
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Destination"; value: backup.status.destination.label || "Unknown" }
            InfoPair { label: "Repository"; value: backup.repositoryText }
            InfoPair {
              visible: !backup.offsite
              label: "Warning"
              value: "Local disk, not off-site"
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: actionColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.actions
              ActionRow {
                required property var modelData
                required property int index
                width: actionColumn.width
                action: modelData
                rowIndex: index
              }
            }
          }

          Column {
            visible: backup.snapshots.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "RECENT BACKUPS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: snapshotColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: backup.snapshots
                SnapshotRow {
                  required property var modelData
                  required property int index
                  width: snapshotColumn.width
                  snapshot: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property var action: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "actions" && root.actionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "actions"
        root.actionIndex = actionRow.rowIndex
      }
      onClicked: root.runAction(actionRow.action.id)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: actionRow.action ? actionRow.action.glyph : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.action ? actionRow.action.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: actionRow.action ? actionRow.action.detail : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component SnapshotRow: CursorSurface {
    id: snapshotRow
    property var snapshot: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.focusSection === "snapshots" && root.snapshotIndex === rowIndex
    foreground: root.foreground
    implicitHeight: snapshotContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "snapshots"
        root.snapshotIndex = snapshotRow.rowIndex
      }
      onClicked: backup.browse()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: snapshotContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: Model.snapshotLabel(snapshotRow.snapshot, backup.nowMs)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: snapshotRow.snapshot ? String(snapshotRow.snapshot.id || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { id: pairLabel; text: label }

    // Bounded rather than implicit, so a long bucket name elides at the panel
    // edge instead of running under it.
    InfoValue {
      text: value
      width: Math.max(0, parent.width - pairLabel.implicitWidth - parent.spacing)
      horizontalAlignment: Text.AlignRight
    }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
