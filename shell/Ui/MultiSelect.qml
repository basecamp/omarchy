import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Window
import Quickshell.Io
import qs.Commons

// Searchable multi-select dropdown. Trigger shape matches Dropdown /
// SearchableDropdown; the popup shows a search field, an optional refresh
// button, and a checkbox list. Click rows to toggle. Use when callers
// need to pick zero or more items from a (possibly long, possibly
// dynamic) list.
//
// Options are either:
//   - static `options`: string[] or [{ value, label, description? }]
//   - dynamic `optionsCommand`: argv array. The command's stdout is
//     parsed as JSON when it trims to start with `[`, otherwise as
//     one option per non-empty newline. Re-runs whenever the popup opens
//     and via the refresh button.
//
// `values` is the persisted selection — always an array of strings.
// Emits `changed(values)` whenever the selection mutates.
Item {
  id: root

  property string label: ""
  property var values: []
  property var options: []
  property var optionsCommand: []
  property string optionsCommandCwd: ""
  property string placeholderText: "Search..."
  property string emptyText: "No options"
  property string noSelectionText: "None selected"
  property string triggerLabel: ""
  property bool showLabel: true

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int popupMinHeight: Style.spacing.searchablePopupMinHeight

  property bool hasCursor: false

  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(var values)
  signal hovered(bool isHovered)

  // Loaded options after merging static + dynamic. Always normalized
  // into the [{ value, label, description }] shape for delegate use.
  property var resolvedOptions: []
  property bool loadingOptions: false
  property string optionsError: ""

  function normalizeOption(o) {
    if (o && typeof o === "object") {
      return {
        value: String(o.value),
        label: String(o.label !== undefined ? o.label : o.value),
        description: o.description ? String(o.description) : ""
      }
    }
    var s = String(o)
    return { value: s, label: s, description: "" }
  }

  // QML schema arrays sometimes arrive as JSValue lists that fail
  // `Array.isArray`. arrayFrom accepts anything array-like (`.length`
  // numeric) and returns a real JS array so the rest of the component can
  // rely on standard array operations.
  function arrayFrom(v) {
    if (!v || typeof v.length !== "number" || typeof v === "string") return []
    var out = []
    for (var i = 0; i < v.length; i++) out.push(v[i])
    return out
  }

  function normalizeAll(arr) {
    var out = []
    var src = arrayFrom(arr)
    var seen = ({})
    for (var i = 0; i < src.length; i++) {
      var n = normalizeOption(src[i])
      if (!n.value) continue
      if (seen[n.value]) continue
      seen[n.value] = true
      out.push(n)
    }
    return out
  }

  function valueSet() {
    var set = ({})
    var arr = arrayFrom(values)
    for (var i = 0; i < arr.length; i++) set[String(arr[i])] = true
    return set
  }

  function isSelected(value) {
    var set = valueSet()
    return !!set[String(value)]
  }

  function toggleValue(value) {
    var v = String(value)
    var arr = arrayFrom(values)
    var idx = arr.indexOf(v)
    if (idx === -1) arr.push(v)
    else arr.splice(idx, 1)
    root.values = arr
    root.changed(arr)
  }

  function selectionLabel() {
    var arr = arrayFrom(values)
    if (arr.length === 0) return ""
    var labels = []
    var byValue = ({})
    for (var i = 0; i < resolvedOptions.length; i++)
      byValue[resolvedOptions[i].value] = resolvedOptions[i].label
    for (var j = 0; j < arr.length; j++)
      labels.push(byValue[String(arr[j])] || String(arr[j]))
    if (labels.length <= 3) return labels.join(", ")
    return arr.length + " selected"
  }

  property var filtered: resolvedOptions
  function recomputeFiltered() {
    var q = searchField.text.toLowerCase()
    if (!q) { filtered = resolvedOptions; return }
    var out = []
    for (var i = 0; i < resolvedOptions.length; i++) {
      var o = resolvedOptions[i]
      if (o.label.toLowerCase().indexOf(q) !== -1
          || o.description.toLowerCase().indexOf(q) !== -1
          || o.value.toLowerCase().indexOf(q) !== -1) out.push(o)
    }
    filtered = out
  }

  function rebuildFromStatic() {
    resolvedOptions = normalizeAll(options)
    recomputeFiltered()
  }

  // Parse stdout from a dynamic optionsCommand into `{ options, error }`.
  // Output starting with `[` is parsed strictly as JSON — a malformed array
  // surfaces as an error rather than silently falling back to newline
  // parsing, which would render the broken text as a literal option label.
  // Output not starting with `[` is treated as one value per non-empty line.
  function parseCommandOutput(text) {
    var raw = String(text || "").trim()
    if (raw === "") return { options: [], error: "" }
    if (raw.charAt(0) === "[") {
      try {
        var parsed = JSON.parse(raw)
        return { options: parsed, error: "" }
      } catch (e) {
        return { options: [], error: "Options command emitted invalid JSON" }
      }
    }
    var out = []
    var lines = raw.split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line !== "") out.push(line)
    }
    return { options: out, error: "" }
  }

  // Monotonic request id so stale stdout/exit signals from a previous
  // refresh can't clobber the resolvedOptions of a newer refresh, and
  // a runaway command can be detected after a timeout.
  property int refreshSeq: 0
  readonly property int refreshTimeoutMs: 6000

  function refresh() {
    var cmd = arrayFrom(optionsCommand)
    if (cmd.length === 0) {
      rebuildFromStatic()
      return
    }
    refreshSeq++
    loadingOptions = true
    optionsError = ""
    optionsProcess.command = cmd
    optionsProcess.workingDirectory = optionsCommandCwd
    optionsProcess.running = false
    optionsProcess.running = true
    refreshTimeoutTimer.restart()
  }

  Timer {
    id: refreshTimeoutTimer
    interval: root.refreshTimeoutMs
    repeat: false
    onTriggered: {
      if (!root.loadingOptions) return
      optionsProcess.running = false
      root.loadingOptions = false
      root.optionsError = "Options command timed out"
    }
  }

  onOptionsChanged: if (arrayFrom(optionsCommand).length === 0) rebuildFromStatic()
  onOptionsCommandChanged: refresh()
  Component.onCompleted: refresh()

  Process {
    id: optionsProcess
    running: false
    command: []

    property int seq: 0

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (optionsProcess.seq !== root.refreshSeq) return
        var result = root.parseCommandOutput(text)
        if (result.error) {
          root.optionsError = result.error
          root.resolvedOptions = root.normalizeAll(root.options)
        } else {
          var combined = root.arrayFrom(root.options)
          for (var j = 0; j < result.options.length; j++) combined.push(result.options[j])
          root.resolvedOptions = root.normalizeAll(combined)
        }
        root.recomputeFiltered()
        root.loadingOptions = false
        refreshTimeoutTimer.stop()
      }
    }

    onRunningChanged: if (running) seq = root.refreshSeq

    onExited: function(exitCode, exitStatus) {
      if (seq !== root.refreshSeq) return
      refreshTimeoutTimer.stop()
      if (exitCode !== 0) {
        root.loadingOptions = false
        root.optionsError = "Options command exited " + exitCode
      }
    }
  }

  implicitWidth: Style.spacing.searchableDropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.selectionLabel() || root.triggerLabel || root.noSelectionText
        color: root.selectionLabel() ? root.foreground : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      QQC.Popup {
        id: popup
        // Reparent to the window's content item so the popup is free of any
        // clipping ancestor. Position
        // and available height are recomputed on open and any time the
        // trigger's geometry changes, since a binding on mapToItem alone
        // won't reliably re-evaluate when ancestors scroll or resize.
        parent: trigger.Window.window ? trigger.Window.window.contentItem : trigger
        property real _anchorX: 0
        property real _anchorY: 0
        property real _availableBelow: 0
        readonly property real _windowHeight: parent ? parent.height : 0
        readonly property real _idealContent: resultList.contentHeight + Style.space(50)
        readonly property real _maxRowsHeight: root.popupRowHeight * 6 + 5 * Style.spacing.labelGap + Style.space(50)

        function reposition() {
          if (!parent) return
          var p = trigger.mapToItem(parent, 0, trigger.height + Style.spacing.xxs)
          _anchorX = p.x
          _anchorY = p.y
          _availableBelow = Math.max(0, _windowHeight - _anchorY - Style.space(12))
        }

        x: _anchorX
        y: _anchorY
        width: trigger.width
        // Clamp to whatever fits below the trigger; don't force popupMinHeight
        // when there isn't room, otherwise the popup overflows the window.
        implicitHeight: Math.min(_availableBelow, _idealContent, _maxRowsHeight)
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        Connections {
          target: trigger
          function onXChanged() { popup.reposition() }
          function onYChanged() { popup.reposition() }
          function onWidthChanged() { popup.reposition() }
          function onHeightChanged() { popup.reposition() }
        }

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          reposition()
          searchField.text = ""
          root.refresh()
          root.recomputeFiltered()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onClosed: searchField.text = ""

        contentItem: Column {
          spacing: 0

          Item {
            id: searchHeader
            width: parent.width
            height: root.popupRowHeight + Style.spacing.controlPaddingX

            Row {
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              spacing: Style.spacing.rowGap

              TextField {
                id: searchField
                width: parent.width - refreshButton.width - parent.spacing
                height: parent.height
                placeholderText: root.placeholderText
                foreground: root.foreground
                accent: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body

                onTextChanged: {
                  root.recomputeFiltered()
                  if (resultList.count > 0) resultList.currentIndex = 0
                }

                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) {
                    popup.close(); event.accepted = true
                  } else if (event.key === Qt.Key_Down) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.forceActiveFocus()
                    }
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (resultList.count > 0) {
                      resultList.currentIndex = 0
                      resultList.toggleCurrent()
                    }
                    event.accepted = true
                  }
                }
              }

              BorderSurface {
                id: refreshButton
                visible: root.arrayFrom(root.optionsCommand).length > 0
                enabled: !root.loadingOptions
                width: parent.height
                height: parent.height
                radius: Style.cornerRadius
                color: refreshHover.hovered
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : Style.normalFillFor(root.foreground, root.accent)
                borderSpec: refreshHover.hovered
                  ? Border.controlSpec("hover-cursor", root.foreground, root.accent)
                  : Border.controlSpec("normal", root.foreground, root.accent)

                Text {
                  anchors.centerIn: parent
                  text: root.loadingOptions ? "󰦖" : "󰑐"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body

                  RotationAnimator on rotation {
                    running: root.loadingOptions
                    from: 0; to: 360
                    duration: 800
                    loops: Animation.Infinite
                  }
                }

                HoverHandler { id: refreshHover }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.refresh()
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.10)
          }

          Item {
            width: parent.width
            height: popup.height - searchHeader.height - Style.spacing.xxs - 1

            Text {
              anchors.centerIn: parent
              visible: resultList.count === 0
              text: root.loadingOptions ? "Loading…" : (root.optionsError !== "" ? root.optionsError : root.emptyText)
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ListView {
              id: resultList
              anchors.fill: parent
              spacing: Style.spacing.labelGap
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.filtered
              currentIndex: -1
              keyNavigationEnabled: false

              function toggleCurrent() {
                if (currentIndex < 0 || currentIndex >= root.filtered.length) return
                root.toggleValue(root.filtered[currentIndex].value)
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === Qt.Key_Down || event.text === "j") {
                  if (resultList.currentIndex >= resultList.count - 1) {
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex + 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || event.text === "k") {
                  if (resultList.currentIndex <= 0) {
                    searchField.forceActiveFocus()
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex - 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                           || event.key === Qt.Key_Space) {
                  resultList.toggleCurrent(); event.accepted = true
                }
              }

              delegate: Rectangle {
                required property var modelData
                required property int index

                readonly property bool selected: root.isSelected(modelData.value)

                width: resultList.width
                height: Math.max(root.popupRowHeight, rowContent.implicitHeight + Style.spacing.rowPaddingX)
                color: index === resultList.currentIndex
                  ? Style.hoverFillFor(root.foreground, root.accent)
                  : "transparent"

                Row {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.spacing.controlPaddingX
                  anchors.rightMargin: Style.spacing.controlPaddingX
                  spacing: Style.spacing.rowGap

                  BorderSurface {
                    id: checkbox
                    width: Style.space(16)
                    height: Style.space(16)
                    radius: Math.max(2, Style.cornerRadius / 2)
                    anchors.verticalCenter: parent.verticalCenter
                    color: selected ? Style.selectedFillFor(root.foreground, root.accent) : "transparent"
                    borderSpec: selected
                      ? Border.controlSpec("selected", root.foreground, root.accent)
                      : Border.controlSpec("normal", root.foreground, root.accent)

                    Text {
                      anchors.centerIn: parent
                      visible: selected
                      text: "✓"
                      color: Style.selectedStateColor(root.foreground, root.accent)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(checkbox.height * 0.85)
                      font.bold: true
                    }
                  }

                  Column {
                    width: parent.width - checkbox.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xxs

                    Text {
                      text: modelData.label
                      color: index === resultList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      visible: text !== ""
                      text: modelData.description
                      color: Qt.darker(root.foreground, 1.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: resultList.currentIndex = parent.index
                  onClicked: root.toggleValue(modelData.value)
                }
              }
            }
          }
        }
      }
    }
  }
}
