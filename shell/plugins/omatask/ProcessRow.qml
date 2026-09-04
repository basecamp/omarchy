import QtQuick
import qs.Commons
import "Model.js" as Model

// One process. The compact form (bar panel) shows name, CPU, and memory; the
// detailed form (overlay) adds pid, user, thread count, and the full command.
Rectangle {
  id: root

  // Dimming has to know what it is dimming *against*. dim() only reads as
  // "less prominent" on a dark ground; on a light theme it makes secondary text
  // darker — and therefore louder — than the primary text it sits behind. This
  // moves toward the background either way.
  readonly property bool groundIsDark: Model.groundIsDark(root.ground)
  function dim(c, amount) { return Model.dim(root.ground, c, amount) }

  // The surface this sits on, so dim() knows which way to move.
  property color ground: Color.popups.background

  property var process: ({})
  property bool detailed: false
  property bool selected: false
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family
  // "Eating the machine" has to be measured against the machine. CPU here is
  // on the per-core scale — 100% is one core, so the ceiling is coreCount×100 —
  // and a fixed threshold on that scale means wildly different things on
  // different hardware: 50% is an eighth of a 4-core laptop but a sixtieth of a
  // 32-thread desktop, where a browser sits above it permanently and the tint
  // stops meaning anything. So the test is a share of total capacity.
  property real machineCapacity: 100      // coreCount × 100; 100 until told
  property real hotShare: 0.2             // a fifth of the machine

  property bool expandable: false
  property bool expanded: false
  // An application row aggregates a whole systemd scope, so it counts member
  // processes where a process row shows a pid, and reports I/O stall where a
  // process reports its own runqueue wait.
  property bool appMode: false
  // Depth in the process tree; 0 in the flat and application views.
  property int depth: 0
  // Flat process view shows runqueue wait here; the tree shows the user,
  // because indentation already costs the row horizontal space.
  property bool showWait: false

  signal activated()
  signal expandToggled()
  signal killRequested(string signalName)

  readonly property real cpuValue: Number(process.cpu) || 0
  readonly property real cpuShare: machineCapacity > 0 ? cpuValue / machineCapacity : 0
  readonly property bool hot: cpuShare >= hotShare
  // Name, CPU, memory, and the kill button are always present (three gaps);
  // the chevron adds one more and the detailed pid/user columns add two.
  readonly property int gapCount: 3 + (expandable ? 1 : 0) + (detailed ? 2 : 0)

  width: parent ? parent.width : implicitWidth
  height: Style.spacing.popupRowHeight
  radius: Style.space(4)
  color: selected ? Style.selectedFillFor(foreground, accent, urgent)
    : (hover.hovered ? Style.hoverFillFor(foreground, accent, urgent) : "transparent")

  Behavior on color { ColorAnimation { duration: 120 } }

  HoverHandler { id: hover }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    onClicked: root.activated()
  }

  Row {
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(4)
    spacing: Style.space(8)

    // Disclosure for the thread list. Only meaningful on a process with more
    // than one thread, so single-threaded rows get the space but not the arrow.
    Item {
      id: chevron
      visible: root.expandable
      width: visible ? Style.space(16) : 0
      height: parent.height

      Text {
        anchors.centerIn: parent
        visible: Number(root.process.threads) > 1
        text: root.expanded ? "▾" : "▸"
        color: root.expanded ? root.accent : dim(root.foreground, 1.6)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        enabled: Number(root.process.threads) > 1
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expandToggled()
      }
    }

    Text {
      id: pidText
      visible: root.detailed
      width: visible ? Style.space(56) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.appMode ? String(root.process.procs || "") : String(root.process.pid || "")
      horizontalAlignment: Text.AlignRight
      color: dim(root.foreground, 1.5)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Name and command share one column: the name is what you scan for, the
    // command is what tells two identical names apart. It takes whatever the
    // fixed columns leave — Row only puts spacing between *visible* children,
    // so the gap count tracks which optional columns are on.
    Column {
      id: nameColumn
      // Tree rows step their text right by depth. The indent is applied inside
      // this column, never to its geometry: a Row positions its children in
      // sequence, so it owns their x and an `x:` binding here is ignored while
      // a width shrunk by the indent still pulls USER, CPU and MEMORY left by
      // that much. Every nested row then drifts further out of line with the
      // header than the one above it.
      readonly property real indent: root.depth * Style.space(13)
      width: parent.width - parent.spacing * root.gapCount
        - chevron.width - pidText.width - userText.width
        - Style.space(60) - Style.space(72) - killButton.width
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0

      Text {
        width: parent.width
        leftPadding: nameColumn.indent
        text: String(root.process.name || "")
        elide: Text.ElideRight
        color: root.hot ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: root.hot
      }

      Text {
        visible: root.detailed
        width: parent.width
        leftPadding: nameColumn.indent
        height: visible ? implicitHeight : 0
        // An application's second line names the systemd scope it came from,
        // which is what distinguishes two scopes that resolve to the same
        // binary — the Hyprland-launched Chromium from the XDG-activated one.
        text: {
          if (!root.appMode) return Model.shortCommand(root.process.cmd, root.process.name)
          // A merged row's unit name is no longer the whole truth, so it says
          // how many scopes it covers instead.
          var scopes = Number(root.process.scopes) || 1
          return scopes > 1 ? scopes + " scopes merged" : String(root.process.unit || "")
        }
        elide: Text.ElideRight
        color: dim(root.foreground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: userText
      visible: root.detailed
      width: visible ? Style.space(64) : 0
      anchors.verticalCenter: parent.verticalCenter
      // Stall and wait are the "why is this slow" numbers, so they earn the
      // urgent tint; the owning user is just context.
      readonly property real stall: root.appMode
        ? (Number(root.process.ioStall) || 0)
        : (Number(root.process.wait) || 0)
      readonly property bool stalling: stall >= 20
      text: {
        if (root.appMode) return stall > 0 ? stall.toFixed(1) + "%" : "—"
        if (root.depth > 0 || !root.showWait) return String(root.process.user || "")
        return stall > 0 ? stall.toFixed(1) + "%" : "—"
      }
      horizontalAlignment: (root.appMode || root.showWait) && root.depth === 0
        ? Text.AlignRight : Text.AlignLeft
      elide: Text.ElideRight
      color: stalling ? root.urgent : dim(root.foreground, 1.5)
      font.bold: stalling
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      width: Style.space(60)
      anchors.verticalCenter: parent.verticalCenter
      text: root.cpuValue.toFixed(1) + "%"
      horizontalAlignment: Text.AlignRight
      color: root.hot ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: root.hot
    }

    Text {
      width: Style.space(72)
      anchors.verticalCenter: parent.verticalCenter
      text: Model.formatBytes(root.appMode ? root.process.mem : root.process.rss)
      horizontalAlignment: Text.AlignRight
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Kill affordance stays hidden until the row is hovered or selected, so a
    // list at rest is a readout rather than a wall of destructive buttons.
    Item {
      id: killButton
      width: Style.space(22)
      height: parent.height
      opacity: (hover.hovered || root.selected) && !root.appMode ? 1 : 0

      Behavior on opacity { NumberAnimation { duration: 120 } }

      Rectangle {
        anchors.centerIn: parent
        width: Style.space(18)
        height: Style.space(18)
        radius: Style.space(3)
        color: killArea.containsMouse
          ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.22)
          : "transparent"

        Text {
          anchors.centerIn: parent
          text: "✕"
          color: killArea.containsMouse ? root.urgent : dim(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      MouseArea {
        id: killArea
        anchors.fill: parent
        enabled: hover.hovered || root.selected
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // Left asks the process to exit, right insists. Same split as
        // htop's SIGTERM/SIGKILL, without a modal in the way.
        onClicked: function(mouse) {
          root.killRequested(mouse.button === Qt.RightButton ? "KILL" : "TERM")
        }
      }
    }
  }
}
