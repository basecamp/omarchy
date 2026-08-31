import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  required property string omarchyPath

  property string requestId: ""
  property string stateDir: ""
  property var request: ({})
  property bool opened: false
  property bool submitting: false
  property int selectedIndex: 0

  readonly property string kind: String(request.kind || "")
  readonly property int readCount: Number(request.read || 0)
  readonly property int leaveCount: Number(request.leave || 0)
  readonly property int feedCount: Number(request.count || 0)
  readonly property string title: kind === "triage"
    ? "Mark reviewed articles as read?"
    : "Add recommended feeds?"
  readonly property string primaryDetail: kind === "triage"
    ? readCount + (readCount === 1 ? " article will" : " articles will") + " be marked read"
    : feedCount + (feedCount === 1 ? " validated feed will" : " validated feeds will") + " be added to Newsboat"
  readonly property string secondaryDetail: kind === "triage"
    ? leaveCount + (leaveCount === 1 ? " recommendation will" : " recommendations will") + " stay unread"
    : "You can review the subscriptions in Feeds"
  readonly property string confirmText: kind === "triage"
    ? "Mark " + readCount + " read"
    : "Add " + feedCount + (feedCount === 1 ? " feed" : " feeds")
  readonly property var targetScreen: {
    var screens = Quickshell.screens || []
    var monitor = Hyprland.focusedMonitor
    var focusedName = monitor ? String(monitor.name || "") : ""
    for (var i = 0; i < screens.length; i++) {
      if (focusedName && String(screens[i].name || "") === focusedName) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function launch(dir, id) {
    var nextDir = String(dir || "")
    var nextId = String(id || "")
    if (!nextDir.startsWith("/")) return "invalid"
    if (!/^[A-Za-z0-9_-]{8,64}$/.test(nextId)) return "invalid"
    if (confirmationProcess.running || opened) {
      return stateDir === nextDir && requestId === nextId ? "ok" : "busy"
    }

    stateDir = nextDir
    requestId = nextId
    request = ({})
    opened = false
    submitting = false
    selectedIndex = 0
    confirmationProcess.command = [root.omarchyPath + "/bin/omarchy-newsboat-confirm", "--bridge", nextDir, nextId]
    confirmationProcess.running = true
    return "ok"
  }

  function status(id) {
    return confirmationProcess.running && requestId === String(id || "") ? "active" : "inactive"
  }

  function cancel(id) {
    if (requestId !== String(id || "")) return "unknown"
    opened = false
    if (confirmationProcess.running) confirmationProcess.running = false
    reset()
    return "ok"
  }

  function reset() {
    opened = false
    submitting = false
    request = ({})
    stateDir = ""
    requestId = ""
    selectedIndex = 0
  }

  function loadDescriptor(line) {
    if (opened || submitting) return
    try {
      var parsed = JSON.parse(String(line || ""))
      var validTriage = parsed.kind === "triage"
        && Number.isInteger(parsed.read) && parsed.read >= 0
        && Number.isInteger(parsed.leave) && parsed.leave >= 0
      var validScout = parsed.kind === "scout"
        && Number.isInteger(parsed.count) && parsed.count >= 1 && parsed.count <= 5
      if (!validTriage && !validScout) throw new Error("invalid descriptor")
      request = parsed
      opened = true
      selectedIndex = 0
      Qt.callLater(function() {
        if (root.opened) keyCatcher.forceActiveFocus()
      })
    } catch (e) {
      console.warn("Newsboat confirmation descriptor failed:", e)
      confirmationProcess.running = false
    }
  }

  function decide(decision) {
    if (!opened || submitting || !confirmationProcess.running) return
    submitting = true
    opened = false
    confirmationProcess.write(decision + "\n")
  }

  function moveSelection() {
    selectedIndex = selectedIndex === 0 ? 1 : 0
  }

  Process {
    id: confirmationProcess
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.loadDescriptor(line) } }
    onExited: root.reset()
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen
    visible: root.opened
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-newsboat-confirmation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.decide("declined")
      }
    }

    BorderSurface {
      id: card
      width: Math.min(panel.width - Style.space(32), Style.space(440))
      height: cardColumn.implicitHeight + card.contentTopInset + card.contentBottomInset
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.normalBorderWidth))
      padding: Style.spacing.panelPadding
      radius: Style.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.decide("declined")
            event.accepted = true
          } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right
                     || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.moveSelection()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.decide(root.selectedIndex === 0 ? "declined" : "approved")
            event.accepted = true
          }
        }
      }

      Column {
        id: cardColumn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.space(18)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.title
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Column {
          width: parent.width
          spacing: Style.spacing.rowGap

          DetailRow {
            width: parent.width
            glyph: "\uf00c"
            detail: root.primaryDetail
          }

          DetailRow {
            width: parent.width
            glyph: "\uf06e"
            detail: root.secondaryDetail
          }
        }

        Row {
          anchors.right: parent.right
          spacing: Style.spacing.controlGap

          Button {
            text: "Cancel"
            focusable: false
            bordered: false
            hasCursor: root.selectedIndex === 0
            foreground: Color.popups.text
            onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 0 }
            onClicked: root.decide("declined")
          }

          Button {
            text: root.confirmText
            focusable: false
            bordered: false
            hasCursor: root.selectedIndex === 1
            foreground: Color.accent
            accent: Color.accent
            onHovered: function(isHovered) { if (isHovered) root.selectedIndex = 1 }
            onClicked: root.decide("approved")
          }
        }
      }
    }
  }

  component DetailRow: Row {
    required property string glyph
    required property string detail
    spacing: Style.spacing.controlGap

    Text {
      width: Style.space(18)
      textFormat: Text.PlainText
      text: parent.glyph
      color: Color.accent
      font.family: Style.font.menuFamily
      font.pixelSize: Style.font.body
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      width: parent.width - Style.space(18) - parent.spacing
      textFormat: Text.PlainText
      text: parent.detail
      color: Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }
  }
}
