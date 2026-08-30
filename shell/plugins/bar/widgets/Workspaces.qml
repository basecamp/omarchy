import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // 1-5 are always offered; any other workspace appears once Hyprland has
  // created it, however high its id. Special workspaces carry negative ids
  // and stay out.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  readonly property int highestWorkspaceId: {
    var ids = root.workspaceIds()
    return ids[ids.length - 1]
  }

  function focusWorkspace(id) {
    if (!root.bar) return

    var workspaceAction = "hl.dsp.focus({ workspace = \"" + id + "\", on_current_monitor = true })"
    var command = "hyprctl dispatch " + Util.shellQuote(workspaceAction)

    if (root.screenName !== "") {
      var monitorAction = "hl.dsp.focus({ monitor = \"" + root.screenName + "\" })"
      command = "hyprctl dispatch " + Util.shellQuote(monitorAction) + " && " + command
    }

    root.bar.run(command)
  }

  // Names come from this widget's shell.json entry, keyed by workspace id:
  //   { "id": "omarchy.workspaces", "names": { "1": "term", "2": "web" } }
  // omarchy-hyprland-workspace-name writes them; the bar patches settings in
  // place, so a rename lands without a restart. A hand-edited name longer
  // than the command allows is cut rather than left to widen the bar.
  readonly property int maxNameLength: 16
  readonly property var names: root.setting("names", {})

  function nameFor(id) {
    var value = names && typeof names === "object" ? names[String(id)] : undefined
    if (typeof value !== "string") return ""
    var characters = Array.from(value)
    return characters.length > maxNameLength ? characters.slice(0, maxNameLength - 1).join("") + "\u2026" : value
  }

  // The widget id is the layout entry the names sit on, so a cloned widget
  // edits its own entry rather than the built-in one.
  function runNameCommand(args) {
    if (!root.bar) return
    root.bar.run("omarchy-hyprland-workspace-name " + args + " --widget " + Util.shellQuote(root.moduleName))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool visibleOnMonitor: workspace !== null && workspace.active
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        // 10 is written as "0" after its SUPER+0 key, but only while it ends
        // the row: between 9 and 11 a literal "10" reads as the number it is.
        readonly property string numeral: (modelData === 10 && root.highestWorkspaceId <= 10) ? "0" : String(modelData)
        // The focus dot stands in for a numeral the keyboard already knows;
        // past 10 there is no key, so the number is the only identification.
        readonly property bool keyed: modelData <= 10
        // A vertical bar is too narrow for words, so it keeps the numbers.
        readonly property string wsName: root.vertical ? "" : root.nameFor(modelData)

        bar: root.bar
        // A name is never hidden behind the focus dot.
        text: wsName !== "" ? wsName : (focused && keyed ? "\uDB85\uDCFB" : numeral)
        // A tile that keeps its text under focus uses the bar's active colour.
        // Workspaces visible on other monitors use the accent colour instead.
        activeColor: focused ? (root.bar ? root.bar.urgent : Color.urgent) : Color.accent
        active: visibleOnMonitor && (wsName !== "" || !focused || !keyed)
        opacity: occupied || visibleOnMonitor ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        // Horizontal tiles grow when a workspace id needs more room. A
        // vertical bar stays one bar wide and clips unusually long ids; the
        // tooltip still exposes the complete number.
        fixedWidth: root.vertical ? root.barSize : Math.max(Style.space(20), labelWidth + scaledHorizontalMargin * 2)
        fixedHeight: root.barSize
        clip: root.vertical
        // A name's tooltip identifies its workspace. In a vertical bar the
        // tooltip also preserves a long number that cannot fit the slot.
        tooltipText: wsName !== "" ? numeral : (root.vertical && numeral.length > 2 ? numeral : "")
        onPressed: function(button) {
          if (button === Qt.RightButton) root.runNameCommand("--prompt " + modelData)
          else if (button === Qt.MiddleButton) root.runNameCommand("--clear " + modelData)
          else root.focusWorkspace(modelData)
        }
      }
    }
  }
}
