import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "omarchy.input"
  ipcTarget: "omarchy.input"

  property var config: ({
    version: 1,
    primary: "us",
    alternate: "",
    compose: "caps",
    superKey: "super",
    numlock: true,
    sensitivity: 0,
    naturalScroll: false,
    clickfinger: true,
    disableWhileTyping: true
  })
  property var layouts: []
  property var pendingChanges: []
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var composeOptions: [
    { value: "caps", label: "Caps Lock" },
    { value: "ralt", label: "Right Alt" },
    { value: "menu", label: "Menu key" },
    { value: "none", label: "Disabled" }
  ]
  readonly property var superOptions: [
    { value: "super", label: "Super key" },
    { value: "alt", label: "Alt key (swap)" }
  ]
  readonly property var alternateLayouts: [{ value: "", label: "None", description: "One layout" }].concat(layouts)
  readonly property bool dropdownOpen: primaryLayout.popupOpen || alternateLayout.popupOpen
    || composeKey.popupOpen || superKey.popupOpen

  function updateStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (parsed) config = parsed
  }

  function optimistic(key, value) {
    var next = Object.assign({}, config)
    next[key] = value
    config = next
  }

  function setSetting(key, value) {
    optimistic(key, value)
    var queue = pendingChanges.slice()
    queue.push({ key: key, value: String(value) })
    pendingChanges = queue
    runNextChange()
  }

  function runNextChange() {
    if (actionProc.running || pendingChanges.length === 0) return
    var queue = pendingChanges.slice()
    var change = queue.shift()
    pendingChanges = queue
    actionProc.command = ["omarchy-input-config", "set", change.key, change.value]
    actionProc.running = true
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
  }

  function moveCursor(delta) {
    selectedIndex = Math.max(0, Math.min(9, selectedIndex + delta))
    cursorActive = true
  }

  function activateCursor() {
    if (selectedIndex === 0) primaryLayout.toggle()
    else if (selectedIndex === 1) alternateLayout.toggle()
    else if (selectedIndex === 2) composeKey.toggle()
    else if (selectedIndex === 3) superKey.toggle()
    else if (selectedIndex === 4) setSetting("numlock", !config.numlock)
    else if (selectedIndex === 6) setSetting("naturalScroll", !config.naturalScroll)
    else if (selectedIndex === 7) setSetting("clickfinger", !config.clickfinger)
    else if (selectedIndex === 8) setSetting("disableWhileTyping", !config.disableWhileTyping)
    else if (selectedIndex === 9) openAdvancedConfig()
  }

  function adjustCursor(delta) {
    if (selectedIndex !== 5) return
    var next = Math.max(-1, Math.min(1, Number(config.sensitivity || 0) + delta * 0.05))
    setSetting("sensitivity", Math.round(next * 100) / 100)
  }

  function pointCursor(index) {
    cursorActive = true
    selectedIndex = index
  }

  function openAdvancedConfig() {
    Quickshell.execDetached(["omarchy-launch-config-editor", Quickshell.env("HOME") + "/.config/hypr/input.lua"])
    close()
  }

  Component.onCompleted: {
    layoutsProc.running = true
    refresh()
  }

  onOpenedChanged: if (opened) {
    refresh()
    cursorActive = false
    selectedIndex = 0
  }

  Process {
    id: layoutsProc
    command: ["xkbcli", "list", "--load-exotic"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.layouts = Model.layoutOptions(text)
    }
  }

  Process {
    id: stateProc
    command: ["omarchy-input-config", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStatus(text) }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateStatus(text) }
    onRunningChanged: if (!running) root.runNextChange()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Input settings"
    onPressed: function() { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.adjustCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          PanelHero {
            title: "Input"
            meta: Model.heroMeta(root.config)
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "KEYBOARD"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            SearchableDropdown {
              id: primaryLayout
              width: (parent.width - parent.spacing) / 2
              label: "Primary layout"
              value: String(root.config.primary || "us")
              options: root.layouts
              placeholderText: "Find a layout"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.selectedIndex === 0
              onChanged: function(value) { root.setSetting("primary", value) }
              onHovered: function(on) { if (on) root.pointCursor(0) }
            }

            SearchableDropdown {
              id: alternateLayout
              width: (parent.width - parent.spacing) / 2
              label: "Second layout"
              value: String(root.config.alternate || "")
              options: root.alternateLayouts
              placeholderText: "None"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.selectedIndex === 1
              onChanged: function(value) { root.setSetting("alternate", value) }
              onHovered: function(on) { if (on) root.pointCursor(1) }
            }
          }

          Text {
            width: parent.width
            visible: !!root.config.alternate
            text: "Press both Alt keys to switch layouts"
            color: Qt.darker(root.bar.foreground, 1.45)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            Dropdown {
              id: composeKey
              width: (parent.width - parent.spacing) / 2
              label: "Compose key"
              value: String(root.config.compose || "caps")
              options: root.composeOptions
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.selectedIndex === 2
              onChanged: function(value) { root.setSetting("compose", value) }
              onHovered: function(on) { if (on) root.pointCursor(2) }
            }

            Dropdown {
              id: superKey
              width: (parent.width - parent.spacing) / 2
              label: "Super lives on"
              value: String(root.config.superKey || "super")
              options: root.superOptions
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursorActive && root.selectedIndex === 3
              onChanged: function(value) { root.setSetting("superKey", value) }
              onHovered: function(on) { if (on) root.pointCursor(3) }
            }
          }

          Toggle {
            width: parent.width
            label: "Num Lock on startup"
            description: "Start every session with the number pad enabled"
            checked: root.config.numlock === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.selectedIndex === 4
            onClicked: root.setSetting("numlock", !root.config.numlock)
            onHovered: function(on) { if (on) root.pointCursor(4) }
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "POINTER & TOUCHPAD"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: Math.max(pointerLabel.implicitHeight, pointerValue.implicitHeight)

              Text {
                id: pointerLabel
                text: "Pointer speed"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                anchors.left: parent.left
              }

              Text {
                id: pointerValue
                text: {
                  var value = Math.round(Number(root.config.sensitivity || 0) * 100)
                  return value > 0 ? "+" + value + "%" : value + "%"
                }
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
              }
            }

            CursorSurface {
              width: parent.width
              height: pointerSlider.implicitHeight + Style.space(6)
              hasCursor: root.cursorActive && root.selectedIndex === 5
              foreground: root.bar.foreground

              HoverHandler {
                onHoveredChanged: if (hovered) root.pointCursor(5)
              }

              PanelSlider {
                id: pointerSlider
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                bar: root.bar
                minimum: -1
                maximum: 1
                step: 0.05
                value: Number(root.config.sensitivity || 0)
                tickCount: 5
                onReleased: function(value) { root.setSetting("sensitivity", Math.round(value * 100) / 100) }
              }
            }
          }

          Toggle {
            width: parent.width
            label: "Natural scrolling"
            description: "Move content in the same direction as your fingers"
            checked: root.config.naturalScroll === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.selectedIndex === 6
            onClicked: root.setSetting("naturalScroll", !root.config.naturalScroll)
            onHovered: function(on) { if (on) root.pointCursor(6) }
          }

          Toggle {
            width: parent.width
            label: "Two-finger right click"
            description: "Use two fingers instead of the touchpad's lower corner"
            checked: root.config.clickfinger === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.selectedIndex === 7
            onClicked: root.setSetting("clickfinger", !root.config.clickfinger)
            onHovered: function(on) { if (on) root.pointCursor(7) }
          }

          Toggle {
            width: parent.width
            label: "Pause touchpad while typing"
            description: "Prevent accidental pointer movement from your palms"
            checked: root.config.disableWhileTyping === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.selectedIndex === 8
            onClicked: root.setSetting("disableWhileTyping", !root.config.disableWhileTyping)
            onHovered: function(on) { if (on) root.pointCursor(8) }
          }

          Button {
            width: parent.width
            text: "Advanced input config"
            iconText: "󰏫"
            leftAlign: true
            bordered: true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            hasCursor: root.cursorActive && root.selectedIndex === 9
            onClicked: root.openAdvancedConfig()
            onHovered: function(on) { if (on) root.pointCursor(9) }
          }
        }
      }
    }
  }
}
