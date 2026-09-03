import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Drag displays into position. Everything is drawn in logical pixels, which is
// the space Hyprland positions displays in and the space the pointer crosses
// between them — drawing mode sizes would show rectangles whose proportions
// have nothing to do with how the desktop behaves.
//
// Applying a layout can strand the pointer or leave a display dark, and the
// user cannot always click "undo" afterwards, so a change reverts itself
// unless it is confirmed.
Item {
  id: root

  property var shell: null
  property bool opened: false

  // The layout being edited, and the one to go back to.
  property var rects: []
  property var originalRects: []
  property var displays: []
  property string selectedName: ""

  // Rotation is edited alongside position, since turning a display changes the
  // edges it presents and therefore the layout around it. Keyed by display name.
  property var transforms: ({})
  property var originalTransforms: ({})

  // Set while a layout is applied but not yet confirmed.
  property bool awaitingConfirmation: false
  property int secondsLeft: 0

  // Mirroring belongs here rather than in the panel: it is the other answer to
  // how displays relate in space, and it collapses the arrangement to a single
  // display, which is exactly what this canvas draws.
  property string mirroringMonitor: ""
  readonly property bool mirrorEnabled: mirroringMonitor !== ""

  // Offer mirroring against the displays that are actually live, which is what
  // the canvas draws. `omarchy-monitor-state` names its internal and external
  // displays out of `hyprctl monitors all`, so it names ones the user switched
  // off too: gating on those put Mirror above a canvas holding a single
  // rectangle, and pressing it silently re-enabled the panel that was off.
  readonly property bool internalActive: Model.hasActiveDisplay(displays, true)
  readonly property bool externalActive: Model.hasActiveDisplay(displays, false)

  // Mirroring withdraws the mirrored output from the active listing altogether,
  // so the pair test cannot hold while it is on. Keep the row up in that case
  // regardless, or Extend becomes unreachable from the only place offering it.
  readonly property bool mirrorAvailable: mirrorEnabled || (internalActive && externalActive)

  // Mirroring collapses every display onto one region, so there is no
  // arrangement left to edit and the canvas draws the source alone. Writing a
  // position for it would move it out from under the mirror rule, which pins
  // the mirror to where the source was: the two would then cover different
  // regions while still reporting as mirroring, which is the split this branch
  // already had to fix once. Rotating is enough to reach it, since the lone
  // display normalises to 0x0 whatever it was at.
  readonly property bool editable: !mirrorEnabled

  // Switching mode adds or removes an output, and this overlay is anchored to
  // one: mirroring withdraws the mirrored display from Wayland, which leaves
  // the window without a surface while it still holds keyboard focus — an
  // invisible overlay that swallows input until Escape. Close first, so the
  // outputs change with nothing anchored to them.
  function setMirror(enabled) {
    // A layout waiting to be confirmed has to be put back before the outputs
    // are reconfigured under it. Both the revert and the mirror write rules for
    // the same displays, so starting them together would leave the geometry
    // that ends up in the user's config to whichever finished last. Hold the
    // mode switch until the revert has landed.
    //
    // A revert already on its way counts too: it clears the prompt as it starts
    // but keeps writing for a moment afterwards, and a second press landing in
    // that gap would race it just the same.
    if (awaitingConfirmation || closeWhenApplied) {
      pendingMirror = enabled
      if (awaitingConfirmation) revertLayout()
      return
    }

    applyMirror(enabled)
  }

  function applyMirror(enabled) {
    mirrorProc.command = ["omarchy-hyprland-monitor-internal-mirror", enabled ? "on" : "off"]
    if (!mirrorProc.running) mirrorProc.running = true
    close()
  }

  readonly property int snapThreshold: 60
  readonly property int nudgeStep: 40

  readonly property color scrim: Util.alpha(Color.background, 0.97)

  function scheduleReopen(delay) {
    reopen.interval = delay
    reopen.restart()
  }

  function open(payloadJson) {
    refresh()

    // Drop any stale window first. A previous apply may have reconfigured the
    // outputs and taken the surface with it, leaving this believing it is still
    // open — in which case showing it again would do nothing at all. Dropping
    // it only needs to land before the window is stood back up, so this hands
    // the change to the next event loop turn.
    opened = false
    scheduleReopen(0)
  }

  // A layout that has been applied but not confirmed is only safe because it
  // puts itself back. Every way out of that prompt other than Keep has to
  // revert, including the ones that are not a decision about the layout at all:
  // clicking the scrim, the toggle hotkey, a hide over IPC, switching to
  // Mirror. Dropping the timer instead would make an arrangement the user could
  // not see permanent, which is the one thing the prompt exists to prevent.
  function close() {
    if (awaitingConfirmation) {
      revertLayout()
      return
    }
    dismiss()
  }

  function dismiss() {
    opened = false
    closeWhenApplied = false
    pendingMirror = null
    reopen.stop()
    revertTimer.stop()
    countdown.stop()
    awaitingConfirmation = false
  }

  function toggle() {
    if (opened) close()
    else open("")
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!mirrorStateProc.running) mirrorStateProc.running = true
  }

  function selectedRect() {
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].name === selectedName) return rects[i]
    }
    return null
  }

  function replaceRect(next) {
    var out = []
    for (var i = 0; i < rects.length; i++) {
      out.push(rects[i].name === next.name ? next : rects[i])
    }
    rects = out
  }

  // Move a display and pull it onto its neighbours' edges. Both the pointer
  // and the keyboard go through here so they cannot disagree about what a
  // valid position is.
  function moveTo(name, x, y) {
    var moving = null
    var others = []
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].name === name) moving = rects[i]
      else others.push(rects[i])
    }
    if (!moving) return

    // Snap onto a neighbour's edge, push clear of anything still overlapping,
    // then pull the display against a neighbour if it ended up floating. A drop
    // always lands somewhere the layout can actually be used: no overlap, and
    // no gap for the pointer to fall into.
    var moved = { name: name, x: Math.round(x), y: Math.round(y), width: moving.width, height: moving.height }
    moved = Model.pushOut(Model.snap(moved, others, root.snapThreshold), others)
    replaceRect(Model.pushOut(Model.attach(moved, others), others))
  }

  function nudge(dx, dy) {
    if (!editable) return

    var rect = selectedRect()
    if (!rect) return
    moveTo(rect.name, rect.x + dx * root.nudgeStep, rect.y + dy * root.nudgeStep)
  }

  function selectNext(delta) {
    if (rects.length === 0) return
    var index = 0
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].name === selectedName) index = i
    }
    index = (index + delta + rects.length) % rects.length
    selectedName = rects[index].name
  }

  readonly property var normalizedRects: Model.normalized(rects)
  readonly property bool layoutOverlaps: Model.anyOverlap(rects)
  readonly property bool layoutContiguous: Model.isContiguous(rects)
  readonly property bool layoutValid: !layoutOverlaps && layoutContiguous
  // What the canvas draws is normalised, so an edit is judged against the
  // normalised layout: shifting every display by the same amount is not an edit.
  //
  // Writing is judged against where the displays actually are. A layout whose
  // top-left is not already the origin — anything with a display left of or
  // above 0x0 — moves under normalisation, so a display the user never touched
  // can still need a new position. Writing only the ones they dragged would
  // apply a normalised position beside an un-normalised one and leave the gap
  // the canvas just showed them closing.
  readonly property var pendingChanges: {
    var edited = Model.changedPositions(Model.normalized(originalRects), normalizedRects)
    if (Object.keys(edited).length === 0) return edited
    return Model.changedPositions(originalRects, normalizedRects)
  }
  readonly property bool rotationChanged: {
    for (var i = 0; i < displays.length; i++) {
      var name = displays[i].name
      if (transforms.hasOwnProperty(name) && transforms[name] !== (Number(displays[i].transform) || 0)) return true
    }
    return false
  }
  readonly property bool hasChanges: Object.keys(pendingWrites).length > 0

  // Everything that needs writing: displays that moved, plus displays that
  // turned. A rotation changes no position, so it would otherwise be invisible
  // to a position diff.
  readonly property var pendingWrites: {
    var writes = {}
    var changed = pendingChanges
    for (var name in changed) writes[name] = changed[name]

    var current = Model.positionsOf(normalizedRects)
    for (var i = 0; i < displays.length; i++) {
      var display = displays[i]
      if (transforms.hasOwnProperty(display.name) &&
          transforms[display.name] !== (Number(display.transform) || 0) &&
          current.hasOwnProperty(display.name)) {
        writes[display.name] = current[display.name]
      }
    }
    return writes
  }

  function transformOf(name) {
    if (transforms.hasOwnProperty(name)) return transforms[name]
    for (var i = 0; i < displays.length; i++) {
      if (displays[i].name === name) return Number(displays[i].transform) || 0
    }
    return 0
  }

  // Turning a display re-measures it, then settles the layout around the new
  // shape the same way a drag does.
  function rotateSelected() {
    if (!editable) return

    var rect = selectedRect()
    if (!rect) return

    var from = transformOf(rect.name)
    var to = Model.nextTransform(from)

    var others = []
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].name !== rect.name) others.push(rects[i])
    }

    var next = Object.assign({}, transforms)
    next[rect.name] = to
    transforms = next

    var turned = Model.rotated(rect, from, to)
    replaceRect(Model.pushOut(Model.attach(Model.pushOut(turned, others), others), others))
  }

  function scaleOf(name) {
    for (var i = 0; i < displays.length; i++) {
      if (displays[i].name === name) return displays[i].scale
    }
    return 1
  }

  // The mode the display is actually running, to restate in its rule. Hyprland
  // merges monitor rules per identifier and drops whatever a rule leaves out,
  // so a rule saying "preferred" takes a display the user pinned to a mode like
  // 2560x1440@144 and drops it back to whatever the monitor reports as best.
  // Nothing here is trying to change the mode, so say the one already in use.
  function modeOf(name) {
    for (var i = 0; i < displays.length; i++) {
      if (displays[i].name !== name) continue

      var width = Number(displays[i].width)
      var height = Number(displays[i].height)
      var refresh = Number(displays[i].refreshRate)
      if (width > 0 && height > 0 && refresh > 0) return width + "x" + height + "@" + refresh
      break
    }
    return "preferred"
  }

  // Geometry is applied first and then recorded in the user's own monitors.lua,
  // which is where they already write it and where they will edit it next.
  // Keeping it anywhere else means two files describing one display, and
  // whichever Hyprland loads last silently wins.
  function writeLayout(positions) {
    var commands = []
    for (var name in positions) {
      var transform = root.transformOf(name)
      // A layout that could not be saved has to say so. The alternative is the
      // arrangement holding until the next reload and then reverting, with
      // nothing having reported a problem.
      //
      // The fallback is grouped, and the group hangs off the move rather than
      // sitting beside it. Bash gives && and || the same precedence and reads
      // left to right, so an ungrouped `move && save || warn` sends a failed
      // move to the warning about saving, and then carries on to the next
      // display with the whole run still reporting success. Only a failed save
      // is recovered here; a failed move ends the run and says so through the
      // exit status.
      commands.push("hyprctl eval 'hl.monitor({ output = \"" + name + "\", mode = \"" + root.modeOf(name)
        + "\", position = \"" + positions[name] + "\", scale = " + root.scaleOf(name)
        + (transform !== 0 ? ", transform = " + transform : "") + " })'"
        + " && { omarchy-hyprland-monitor-rule " + name
        + " || omarchy-notification-send -g \"" + Model.displayGlyph + "\" "
        + "\"Couldn't save " + name + " to monitors.lua\" "
        + "\"Its rule there could not be identified, so the change lasts until the next reload\""
        + "; }")
    }
    if (commands.length === 0) return false

    // No reload: the rules above are applied directly and then recorded in the
    // user's config for next time, so there is nothing to re-read. That also
    // spares every display a modeset, which is what used to park the pointer in
    // a corner and leave windows sized for geometry on its way out.
    //
    // Windows still keep their dimensions until something makes the workspace
    // lay out again, so re-select it afterwards.
    var script = "workspace=\"$(hyprctl activeworkspace -j | jq -r .id)\"; "
      + commands.join(" && ")
      + " && sleep 0.4"
      + " && hyprctl dispatch \"hl.dsp.focus({ workspace = \\\"$workspace\\\" })\""

    runScript(script)
    return true
  }

  // Every write goes through one process, so a second asked for while the first
  // is still running has to wait its turn. Assigning `command` and `running` to
  // a Process that is already running starts nothing, so the second write would
  // simply be dropped: press Escape during the apply's own settle and the
  // revert never runs, while `closeWhenApplied` still takes the prompt away and
  // leaves the layout applied. Queue it and run it when the first exits.
  function runScript(script) {
    if (applyProc.running) {
      queuedScript = script
      return
    }

    applyProc.command = ["bash", "-c", script]
    applyProc.running = true
  }

  function apply() {
    if (!editable || !hasChanges || !layoutValid) return
    if (!writeLayout(pendingWrites)) return

    awaitingConfirmation = true
    secondsLeft = 15
    countdown.restart()
    revertTimer.restart()

    // Nothing else to do. Applying does not reload Hyprland — writeLayout sets
    // each rule directly, precisely so no display takes a modeset — so the
    // surface this overlay is drawn on outlives the change, and the window can
    // stay exactly where it is while the geometry moves under it. Dropping and
    // raising it here to be safe would be the one thing that made it flash.
  }

  function confirmLayout() {
    awaitingConfirmation = false
    revertTimer.stop()
    countdown.stop()
    originalRects = rects
    close()
  }

  function revertLayout() {
    awaitingConfirmation = false
    revertTimer.stop()
    countdown.stop()

    transforms = originalTransforms
    rects = originalRects

    // Where the displays actually were, not the normalised version of it.
    // Normalising is how the canvas draws a layout and how a new one is written,
    // but putting one back is not writing a new one: a layout that started off
    // the origin, anything with a display left of or above 0x0, would come back
    // shifted, so the fail-safe meant to undo a change would make one of its
    // own and there would be nothing left to undo it with.
    writeLayout(Model.positionsOf(originalRects))

    // Step out once the layout is actually back, not before. Tearing this
    // overlay's surface down while Hyprland is still re-modesetting leaves
    // windows sized for the geometry that is on its way out — the same
    // sequence run from a shell, with no surface to destroy, comes out clean.
    closeWhenApplied = true
  }

  // Every caller goes through scheduleReopen, which sets the interval to suit
  // what it is waiting for; the value here is only what the timer starts life
  // holding.
  Timer {
    id: reopen
    interval: 0
    repeat: false
    onTriggered: {
      root.refresh()
      root.opened = true
    }
  }

  Timer {
    id: revertTimer
    interval: 15000
    repeat: false
    onTriggered: root.revertLayout()
  }

  Timer {
    id: countdown
    interval: 1000
    repeat: true
    onTriggered: if (root.secondsLeft > 0) root.secondsLeft = root.secondsLeft - 1
  }

  Process {
    id: stateProc
    command: ["hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = []
        try {
          parsed = JSON.parse(String(text || "[]"))
        } catch (e) {
          parsed = []
        }

        root.displays = parsed
        if (!root.awaitingConfirmation) {
          root.transforms = ({})

          var seen = ({})
          for (var t = 0; t < parsed.length; t++) seen[parsed[t].name] = Number(parsed[t].transform) || 0
          root.originalTransforms = seen
        }
        var next = Model.logicalRects(parsed)
        root.rects = next
        if (!root.awaitingConfirmation) root.originalRects = next
        if (!root.selectedRect() && next.length > 0) root.selectedName = next[0].name
      }
    }
  }

  property bool closeWhenApplied: false

  // A mode switch asked for while a layout was waiting to be confirmed, held
  // until the revert it triggered has finished writing.
  property var pendingMirror: null

  // A write asked for while another was still running.
  property string queuedScript: ""

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      // Whatever was waiting on this process goes first, and everything that
      // waits on the writing being finished waits for that too.
      if (root.queuedScript !== "") {
        var next = root.queuedScript
        root.queuedScript = ""
        applyProc.command = ["bash", "-c", next]
        applyProc.running = true
        return
      }

      if (!root.closeWhenApplied) return
      root.closeWhenApplied = false

      // Only step out once the layout is actually back. A revert that failed
      // part way leaves the arrangement it was undoing on screen, and closing
      // on it would be the same as never having reverted: the prompt would be
      // gone with the change still applied. Stay up and say so instead.
      if (exitCode !== 0) {
        root.pendingMirror = null
        Quickshell.execDetached(["omarchy-notification-send", "-g", Model.displayGlyph,
          "Couldn't put the previous layout back",
          "The displays are still arranged as they were just applied"])
        return
      }

      // Read before closing: closing clears the state this was waiting on.
      var wanted = root.pendingMirror
      root.pendingMirror = null

      root.close()
      if (wanted !== null) root.applyMirror(wanted)
    }
  }

  // Mirroring reconfigures outputs, so the canvas has to re-read rather than
  // assume: a mirrored display stops being an independent output entirely.
  Process {
    id: mirrorProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) mirrorSettle.restart()
  }

  Timer {
    id: mirrorSettle
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Process {
    id: mirrorStateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        root.mirroringMonitor = String(lines[4] || "").trim()
      }
    }
  }

  PanelWindow {
    id: window

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-display-arrange"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // Clicking away from the displays cancels, matching the image picker.
    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    FocusScope {
      id: keys
      anchors.fill: parent
      focus: root.opened

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.awaitingConfirmation) root.revertLayout()
          else root.close()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.awaitingConfirmation) root.confirmLayout()
          else root.apply()
          event.accepted = true
          return
        }
        if (event.text === "r" || event.text === "R") {
          root.rotateSelected()
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Tab) {
          root.selectNext(1)
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Left || event.text === "h") { root.nudge(-1, 0); event.accepted = true; return }
        if (event.key === Qt.Key_Right || event.text === "l") { root.nudge(1, 0); event.accepted = true; return }
        if (event.key === Qt.Key_Up || event.text === "k") { root.nudge(0, -1); event.accepted = true; return }
        if (event.key === Qt.Key_Down || event.text === "j") { root.nudge(0, 1); event.accepted = true; return }
      }

      Column {
        anchors.centerIn: parent
        spacing: Style.space(20)

        Text {
          text: "ARRANGE DISPLAYS"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
          spacing: Style.space(10)
          visible: root.mirrorAvailable
          anchors.horizontalCenter: parent.horizontalCenter

          Button {
            text: "Extend"
            fontSize: Style.font.body
            foreground: Color.foreground
            fontFamily: Style.font.family
            horizontalPadding: Style.spacing.lg
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: !root.mirrorEnabled
            onClicked: root.setMirror(false)
          }

          Button {
            text: "Mirror"
            fontSize: Style.font.body
            foreground: Color.foreground
            fontFamily: Style.font.family
            horizontalPadding: Style.spacing.lg
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: root.mirrorEnabled
            onClicked: root.setMirror(true)
          }
        }

        // The canvas. Rectangles are the displays at their logical
        // proportions, scaled together so their relative sizes stay honest.
        Item {
          id: canvas
          width: Math.min(window.width - Style.space(160), Style.space(900))
          height: Math.min(window.height - Style.space(260), Style.space(520))
          anchors.horizontalCenter: parent.horizontalCenter

          readonly property int pad: Style.space(40)
          readonly property real fit: Model.fitScale(root.rects, width, height, pad)
          readonly property var box: Model.bounds(root.rects)
          readonly property real offsetX: (width - box.width * fit) / 2 - box.x * fit
          readonly property real offsetY: (height - box.height * fit) / 2 - box.y * fit

          function toCanvasX(x) { return offsetX + x * fit }
          function toCanvasY(y) { return offsetY + y * fit }
          function toLayoutX(x) { return (x - offsetX) / fit }
          function toLayoutY(y) { return (y - offsetY) / fit }

          Repeater {
            model: root.rects

            Rectangle {
              id: tile
              required property var modelData

              readonly property bool isSelected: modelData.name === root.selectedName

              x: canvas.toCanvasX(modelData.x)
              y: canvas.toCanvasY(modelData.y)
              width: modelData.width * canvas.fit
              height: modelData.height * canvas.fit

              radius: Style.cornerRadius
              color: isSelected
                ? Util.alpha(Color.accent, 0.28)
                : Util.alpha(Color.foreground, 0.10)
              border.width: isSelected ? 2 : 1
              border.color: isSelected ? Color.accent : Qt.darker(Color.foreground, 1.5)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  text: tile.modelData.name
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  anchors.horizontalCenter: parent.horizontalCenter
                }

                Text {
                  text: tile.modelData.width + " x " + tile.modelData.height
                    + (root.transformOf(tile.modelData.name) !== 0
                       ? "  ·  " + Model.transformLabel(root.transformOf(tile.modelData.name)) : "")
                  color: Qt.darker(Color.foreground, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }

              // Qt moves the tile during the gesture and the layout is only
              // written on release. Updating the model per mouse move rebuilds
              // the Repeater's delegates underneath the pointer, which destroys
              // the item being dragged mid-gesture.
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeAllCursor
                enabled: !root.awaitingConfirmation && root.editable
                drag.target: tile
                drag.axis: Drag.XAndYAxis
                drag.smoothed: false

                onPressed: root.selectedName = tile.modelData.name

                onReleased: {
                  root.moveTo(tile.modelData.name, canvas.toLayoutX(tile.x), canvas.toLayoutY(tile.y))

                  // Dragging assigned x and y directly, which broke their
                  // bindings; restore them so the tile follows the model again
                  // once snapping has adjusted it.
                  tile.x = Qt.binding(function() { return canvas.toCanvasX(tile.modelData.x) })
                  tile.y = Qt.binding(function() { return canvas.toCanvasY(tile.modelData.y) })
                }
              }
            }
          }
        }

        // Why the layout cannot be applied, rather than a disabled button with
        // no explanation.
        Text {
          text: {
              if (root.awaitingConfirmation) return "KEEP THIS LAYOUT?  " + root.secondsLeft + "s"
            if (root.mirrorEnabled) return "MIRRORING — SWITCH TO EXTEND TO ARRANGE DISPLAYS"
            if (root.layoutOverlaps) return "DISPLAYS OVERLAP"
            if (!root.layoutContiguous) return "DISPLAYS MUST TOUCH — A GAP IS A DEAD ZONE FOR THE POINTER"
            // Nothing to say until something is actually wrong or pending: the
            // controls below name themselves, and a single display has nothing
            // to drag against anyway.
            if (!root.hasChanges) return ""
            return "ENTER TO APPLY  ·  ESC TO CANCEL"
          }
          visible: text !== ""
          color: root.layoutValid || root.awaitingConfirmation ? Qt.darker(Color.foreground, 1.4) : Color.accent
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.1
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Row {
          spacing: Style.space(10)
          anchors.horizontalCenter: parent.horizontalCenter

          Button {
            text: "Rotate " + Model.transformLabel(Model.nextTransform(root.transformOf(root.selectedName)))
            visible: root.editable && !root.awaitingConfirmation && root.selectedName !== ""
            fontSize: Style.font.body
            foreground: Color.foreground
            fontFamily: Style.font.family
            horizontalPadding: Style.spacing.lg
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.rotateSelected()
          }

          Button {
            text: root.awaitingConfirmation ? "Keep" : "Apply"
            visible: root.editable || root.awaitingConfirmation
            foreground: Color.foreground
            fontFamily: Style.font.family
            fontSize: Style.font.body
            horizontalPadding: Style.spacing.lg
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            active: root.awaitingConfirmation
            onClicked: root.awaitingConfirmation ? root.confirmLayout() : root.apply()
          }

          Button {
            text: root.awaitingConfirmation ? "Revert" : "Cancel"
            foreground: Color.foreground
            fontFamily: Style.font.family
            fontSize: Style.font.body
            horizontalPadding: Style.spacing.lg
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.awaitingConfirmation ? root.revertLayout() : root.close()
          }
        }
      }
    }
  }
}
