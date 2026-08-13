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

  // Switching mode adds or removes an output, and this overlay is anchored to
  // one: mirroring withdraws the mirrored display from Wayland, which leaves
  // the window without a surface while it still holds keyboard focus — an
  // invisible overlay that swallows input until Escape. Close first, so the
  // outputs change with nothing anchored to them.
  function setMirror(enabled) {
    mirrorProc.command = ["omarchy-hyprland-monitor-internal-mirror", enabled ? "on" : "off"]
    if (!mirrorProc.running) mirrorProc.running = true
    close()
  }

  readonly property int snapThreshold: 60
  readonly property int nudgeStep: 40

  readonly property color scrim: Util.alpha(Color.background, 0.97)

  // Long enough for Hyprland to finish re-modesetting every display after a
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

  function close() {
    opened = false
    closeWhenApplied = false
    // An apply still in flight must not raise the window again behind a user
    // who has just dismissed it.
    reopenWhenApplied = false
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
  readonly property var pendingChanges: Model.changedPositions(Model.normalized(originalRects), normalizedRects)
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

  // Geometry is applied first and then recorded in the user's own monitors.lua,
  // which is where they already write it and where they will edit it next.
  // Keeping it anywhere else means two files describing one display, and
  // whichever Hyprland loads last silently wins.
  function writeLayout(positions) {
    var commands = []
    for (var name in positions) {
      var transform = root.transformOf(name)
      commands.push("hyprctl eval 'hl.monitor({ output = \"" + name + "\", mode = \"preferred\", position = \""
        + positions[name] + "\", scale = " + root.scaleOf(name)
        + (transform !== 0 ? ", transform = " + transform : "") + " })'")
      // A layout that could not be saved has to say so. The alternative is the
      // arrangement holding until the next reload and then reverting, with
      // nothing having reported a problem.
      commands.push("omarchy-hyprland-monitor-rule " + name
        + " || omarchy-notification-send -g \"" + Model.displayGlyph + "\" "
        + "\"Couldn't save " + name + " to monitors.lua\" "
        + "\"Its rule there could not be identified, so the change lasts until the next reload\"")
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

    applyProc.command = ["bash", "-c", script]
    applyProc.running = true
    return true
  }

  function apply() {
    if (!hasChanges || !layoutValid) return
    if (!writeLayout(pendingWrites)) return

    awaitingConfirmation = true
    secondsLeft = 15
    countdown.restart()
    revertTimer.restart()

    // Applying does not reload Hyprland: writeLayout sets each rule directly,
    // precisely so no display takes a modeset. So there is nothing for the
    // overlay to sit out — it stays up while the geometry moves under it.
    //
    // It is still stood back up once the work finishes, because a compositor
    // that does take the surface leaves this believing it is still open, and
    // the confirm-or-revert prompt has to be there to answer. Waiting on the
    // apply itself rather than on a fixed delay keeps that to a blink.
    reopenWhenApplied = true
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

    var previous = Model.positionsOf(Model.normalized(originalRects))
    writeLayout(previous)

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
  property bool reopenWhenApplied: false

  Process {
    id: applyProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return

      if (root.closeWhenApplied) {
        root.closeWhenApplied = false
        root.reopenWhenApplied = false
        root.close()
        return
      }

      if (root.reopenWhenApplied) {
        root.reopenWhenApplied = false
        // Only a false-to-true turn builds a new surface, so a window that is
        // still up is dropped and immediately raised again rather than left to
        // an assumption about whether the compositor kept it.
        root.opened = false
        root.scheduleReopen(0)
      }
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
                enabled: !root.awaitingConfirmation
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
            visible: !root.awaitingConfirmation && root.selectedName !== ""
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
