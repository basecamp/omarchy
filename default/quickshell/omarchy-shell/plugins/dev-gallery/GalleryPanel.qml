import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Visual reference + live playground for omarchy-shell's common UI
// components. Summoned via:
//   omarchy-shell-ipc shell summon omarchy.dev-gallery "{}"
//
// Every section here renders the REAL component (not a copy) so the
// gallery doubles as a smoke test. When you add a new common component,
// add a section here. Maintenance discipline: this file should ONLY use
// imported common components, never inline reimplementations of them.
Item {
  id: root

  // ---- plugin lifecycle ---------------------------------------------------
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    Qt.callLater(function() {
      if (keyCatcher) keyCatcher.forceActiveFocus()
      ensureCursorVisible(currentTarget())
    })
  }

  // Host-initiated close (`shell hide`). Visibility flips without
  // notifying the host back — it already knows.
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close (Esc, window close button). Tell the shell so its
  // openPanelIds map stays consistent and `toggle` works on the next call.
  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide("omarchy.dev-gallery")
    else window.visible = false
  }

  // ---- host injections ----------------------------------------------------
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var shell: null
  property var manifest: null

  // ---- theme --------------------------------------------------------------
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: "monospace"

  // Fake `bar` for components that take a whole bar object (e.g. Slider).
  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: root.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 26
  }

  // ---- cursor model -------------------------------------------------------
  //
  // The gallery itself uses the same recipe wifi / audio / bluetooth /
  // monitor panels use: focusSection + selectedIndex drive a single
  // highlight that crosses kit primitives uniformly, with j/k walking
  // targets (jumping section boundaries automatically), h/l acting
  // locally (horizontal rows / slider adjustment), Enter activating, and
  // Esc closing. Mouse hover updates the same (focusSection,
  // selectedIndex) so keyboard and pointer never diverge.
  //
  // Plugin authors: copy this section verbatim as a template. Replace
  // the section IDs with whatever your panel needs. The shape
  // (visibleSections, sectionCount, sectionIsHorizontal,
  // sectionAdjustsValue, moveCursor, moveCursorH, activateCursor,
  // ensureCursorVisible, clampCursor) is the canonical pattern.
  property string focusSection: "cursor-surface"
  property int selectedIndex: 0

  // Demo state mutated by activation.
  property string choiceDemoValue: "top"
  property bool toggleDemoOn: true
  property bool toggleSquareOn: false
  property string dropdownDemoValue: "calendar"
  property string searchableDemoValue: ""
  property int numberDemoValue: 15

  readonly property var visibleSections: [
    "cursor-surface", "pill-button", "cursor-pill", "panel-action-button",
    "panel-tool-tip", "slider", "choice-button", "text-field", "number-field",
    "toggle", "dropdown", "searchable-dropdown", "composed"
  ]

  function sectionCount(section) {
    switch (section) {
      case "cursor-surface":      return 3
      case "pill-button":         return 5
      case "cursor-pill":         return 4
      case "panel-action-button": return 4
      case "panel-tool-tip":      return 1
      case "slider":              return 1
      case "choice-button":       return 4
      case "text-field":          return 2
      case "number-field":        return 1
      case "toggle":              return 2
      case "dropdown":            return 1
      case "searchable-dropdown": return 1
      case "composed":            return 2
    }
    return 0
  }

  // True for sections whose primitives lay out horizontally (a row of
  // pills, choice buttons, etc.) — j/k jumps to the next/prev section,
  // h/l walks within the row.
  function sectionIsHorizontal(section) {
    return section === "pill-button"
      || section === "cursor-pill"
      || section === "panel-action-button"
      || section === "choice-button"
  }

  // True for sections where h/l should adjust a value rather than walk.
  function sectionAdjustsValue(section) {
    return section === "slider"
  }

  // Where to land when entering a section from above / below.
  function sectionFirstIndex(section) { return 0 }
  function sectionLastIndex(section) { return Math.max(0, sectionCount(section) - 1) }

  function moveCursor(delta) {
    var sections = visibleSections
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (sectionIsHorizontal(focusSection) || sectionAdjustsValue(focusSection)
        || sectionCount(focusSection) <= 1) {
      // Single-row / horizontal / value-adjust sections: j/k crosses to
      // the next section.
      if (delta > 0 && sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      } else if (delta < 0 && sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = sectionLastIndex(focusSection)
      }
      return
    }
    // Vertical multi-row section: walk within, then cross at boundaries.
    var next = selectedIndex + delta
    if (next < 0) {
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = sectionLastIndex(focusSection)
      }
    } else if (next >= sectionCount(focusSection)) {
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = sectionFirstIndex(focusSection)
      }
    } else {
      selectedIndex = next
    }
  }

  function moveCursorH(delta) {
    if (sectionAdjustsValue(focusSection)) {
      // h/l on the slider section nudges the demo volume by 5%.
      sliderRow.demoVolume = Math.max(0, Math.min(1, sliderRow.demoVolume + delta * 0.05))
      return
    }
    if (!sectionIsHorizontal(focusSection)) return
    var next = selectedIndex + delta
    var max = sectionCount(focusSection) - 1
    if (next < 0) next = 0
    if (next > max) next = max
    selectedIndex = next
  }

  function activateCursor() {
    if (focusSection === "choice-button") {
      var opts = ["top", "right", "bottom", "left"]
      if (selectedIndex >= 0 && selectedIndex < opts.length)
        root.choiceDemoValue = opts[selectedIndex]
      return
    }
    if (focusSection === "toggle") {
      if (selectedIndex === 0) root.toggleDemoOn = !root.toggleDemoOn
      else root.toggleSquareOn = !root.toggleSquareOn
      return
    }
    if (focusSection === "dropdown") {
      demoDropdown.toggle()
      return
    }
    if (focusSection === "searchable-dropdown") {
      demoSearchableDropdown.toggle()
      return
    }
    if (focusSection === "text-field") {
      if (selectedIndex === 0) demoTextField.forceActiveFocus()
      else demoPasswordField.forceActiveFocus()
      return
    }
    if (focusSection === "number-field") {
      numberDemo.field.forceActiveFocus()
      return
    }
    // pill / panel-action-button / cursor-surface / composed: nothing to
    // mutate in a demo, but real consumers would call their clicked().
  }

  function clampCursor() {
    var sections = visibleSections
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = sectionFirstIndex(focusSection)
      return
    }
    if (selectedIndex < 0) selectedIndex = 0
    var max = sectionLastIndex(focusSection)
    if (selectedIndex > max) selectedIndex = max
  }

  // Scroll the gallery so the given Item is fully visible inside
  // scrollArea's viewport, with a 20px breathing margin. Wired into the
  // hasCursor change handler of every cursor target below.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 12
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  FloatingWindow {
    id: window
    title: "Omarchy shell – dev gallery"
    color: root.background
    implicitWidth: 720
    implicitHeight: 760
    minimumSize: Qt.size(560, 520)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("omarchy.dev-gallery")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      function scrollBy(dy) {
        var sb = scrollArea.ScrollBar.vertical
        if (!sb || scrollArea.contentHeight <= scrollArea.height) return
        var newPos = sb.position + dy / scrollArea.contentHeight
        sb.position = Math.max(0, Math.min(1 - sb.size, newPos))
      }

      // Page/Home/End handled here so they bubble up past keyCatcher
      // (which only consumes Esc / Enter / j-k-h-l / x / text keys).
      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_PageDown) {
          focusScope.scrollBy(300); event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          focusScope.scrollBy(-300); event.accepted = true
        } else if (event.key === Qt.Key_Home) {
          scrollArea.ScrollBar.vertical.position = 0
          event.accepted = true
        } else if (event.key === Qt.Key_End) {
          var sb = scrollArea.ScrollBar.vertical
          if (sb) sb.position = Math.max(0, 1 - sb.size)
          event.accepted = true
        }
      }

      // Panel-style key dispatch — the gallery demonstrates the standard,
      // so it USES the standard. j/k walks cursor targets across sections,
      // h/l acts locally (rows + slider adjust), Enter activates the
      // current target, Esc closes. The catcher suspends itself while a
      // dropdown popup or text field owns keyboard input, so typing into
      // the embedded controls doesn't double-drive the panel cursor.
      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: demoDropdown.popupOpen
          || demoSearchableDropdown.popupOpen
          || demoTextField.activeFocus
          || demoPasswordField.activeFocus
        onMoveRequested: function(dx, dy) {
          if (dy !== 0) root.moveCursor(dy)
          else if (dx !== 0) root.moveCursorH(dx)
        }
        onActivateRequested: root.activateCursor()
        onCloseRequested: root.requestClose()

        ScrollView {
          id: scrollArea
          anchors.fill: parent
          anchors.margins: 18
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: scrollArea.availableWidth
          spacing: 22

          // ---- Header ------------------------------------------------------
          Column {
            width: parent.width
            spacing: 4

            Text {
              text: "Omarchy shell · dev gallery"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 18
              font.bold: true
            }
            Text {
              text: "Live previews of every type exported from qs.Ui. Use this as the visual reference when porting panels or building plugins. Scroll for more. Esc to close."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: 11
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- PanelSectionHeader ------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelSectionHeader"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Small-caps-style intro label for a section."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
            }

            Rectangle {
              width: parent.width
              implicitHeight: shCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: shCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                PanelSectionHeader {
                  text: "DNS provider"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                PanelSectionHeader {
                  text: "Wi-Fi networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }
                PanelSectionHeader {
                  text: "Playing"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: 11
                }
              }
            }
          }

          // ---- PanelSeparator ----------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelSeparator"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "1px horizontal rule. Default 0.12 alpha on foreground; tweak via strength."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
            }

            Rectangle {
              width: parent.width
              implicitHeight: sepCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: sepCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                PanelSeparator { foreground: root.foreground }
                PanelSeparator { foreground: root.foreground; strength: 0.25 }
                PanelSeparator { foreground: root.foreground; strength: 0.45 }
              }
            }
          }

          // ---- CursorSurface -----------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "CursorSurface"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Single highlight chrome for keyboard+mouse navigable items. Press h/l (anywhere in this window) to move the demo cursor. The middle item is also marked `current` to show how the two states layer."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: csCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: csCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                Repeater {
                  model: [
                    { "label": "Idle row" },
                    { "label": "Currently-active row (e.g. connected wifi, default sink)" },
                    { "label": "Forget / scan / disabled-ish row" }
                  ]

                  CursorSurface {
                    required property var modelData
                    required property int index
                    width: parent.width
                    implicitHeight: csLabel.implicitHeight + 16
                    hasCursor: root.focusSection === "cursor-surface" && root.selectedIndex === index
                    current: index === 1
                    foreground: root.foreground
                    fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)

                    Text {
                      id: csLabel
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 10
                      anchors.rightMargin: 10
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onContainsMouseChanged: if (containsMouse) {
                        root.focusSection = "cursor-surface"
                        root.selectedIndex = parent.index
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- PillButton --------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PillButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Compact rounded button with optional icon, label, tooltip, and `active` highlight. Used inside panels for inline actions (Refresh, DNS pills, Bluetooth header)."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: pillCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: pillCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 6

                PillButton {
                  text: "DHCP"
                  tooltipText: "Use DNS from DHCP"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  hasCursor: root.focusSection === "pill-button" && root.selectedIndex === 0
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  HoverHandler { onHoveredChanged: if (hovered) { root.focusSection = "pill-button"; root.selectedIndex = 0 } }
                }

                PillButton {
                  text: "Cloudflare"
                  tooltipText: "Set DNS to Cloudflare"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: true
                  hasCursor: root.focusSection === "pill-button" && root.selectedIndex === 1
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  HoverHandler { onHoveredChanged: if (hovered) { root.focusSection = "pill-button"; root.selectedIndex = 1 } }
                }

                PillButton {
                  iconText: "󰑐"
                  tooltipText: "Refresh"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  horizontalPadding: 8
                  verticalPadding: 4
                  hasCursor: root.focusSection === "pill-button" && root.selectedIndex === 2
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  HoverHandler { onHoveredChanged: if (hovered) { root.focusSection = "pill-button"; root.selectedIndex = 2 } }
                }

                PillButton {
                  iconText: "󰂯"
                  text: "On"
                  tooltipText: "Turn Bluetooth off"
                  tooltipBackground: root.background
                  tooltipForeground: root.foreground
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: true
                  hasCursor: root.focusSection === "pill-button" && root.selectedIndex === 3
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  HoverHandler { onHoveredChanged: if (hovered) { root.focusSection = "pill-button"; root.selectedIndex = 3 } }
                }

                PillButton {
                  text: "Apply"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  bordered: true
                  hasCursor: root.focusSection === "pill-button" && root.selectedIndex === 4
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  HoverHandler { onHoveredChanged: if (hovered) { root.focusSection = "pill-button"; root.selectedIndex = 4 } }
                }
              }
            }
          }

          // ---- CursorPill --------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "CursorPill"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "PillButton with panel-cursor wiring. Bind hasCursor to your cursor state and onHovered to update it on mouse enter; clicks come from PillButton's clicked() signal. Use this for any \"pick one in a row\" UI (wifi DNS pills, bluetooth header actions). Click below or press h/l to walk the demo cursor."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: cpRow.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: cpRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 6

                Repeater {
                  model: ["DHCP", "Cloudflare", "Google", "Custom"]
                  CursorPill {
                    required property string modelData
                    required property int index
                    text: modelData
                    foreground: root.foreground
                    tooltipBackground: root.background
                    tooltipForeground: root.foreground
                    fontFamily: root.fontFamily
                    tooltipText: "Pick " + modelData
                    hasCursor: root.focusSection === "cursor-pill" && root.selectedIndex === index
                    active: modelData === "Cloudflare"
                    onHovered: function(h) {
                      if (h) { root.focusSection = "cursor-pill"; root.selectedIndex = index }
                    }
                    onClicked: { root.focusSection = "cursor-pill"; root.selectedIndex = index }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                }
              }
            }
          }

          // ---- PanelActionButton -------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelActionButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "22×22 right-edge action button. Two flavors via hoverColor: default (foreground tint, e.g. confirm) and urgent (red tint, e.g. forget/unpair). Hover and click states are intrinsic; the row that owns it stays responsible for the cursor highlight."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: pabCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: pabCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 18

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Confirm (default flavor)"
                  foreground: root.foreground
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                  hasCursor: root.focusSection === "panel-action-button" && root.selectedIndex === 0
                  onHovered: function(h) {
                    if (h) { root.focusSection = "panel-action-button"; root.selectedIndex = 0 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                }

                PanelActionButton {
                  iconText: "󰅙"
                  tooltipText: "Forget network (urgent flavor)"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                  hasCursor: root.focusSection === "panel-action-button" && root.selectedIndex === 1
                  onHovered: function(h) {
                    if (h) { root.focusSection = "panel-action-button"; root.selectedIndex = 1 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                }

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Disabled — type a passphrase first"
                  foreground: root.foreground
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                  enabled: false
                  hasCursor: root.focusSection === "panel-action-button" && root.selectedIndex === 2
                  onHovered: function(h) {
                    if (h) { root.focusSection = "panel-action-button"; root.selectedIndex = 2 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                }

                PanelActionButton {
                  iconText: "󰒓"
                  tooltipText: "Focusable (settings form button)"
                  foreground: root.foreground
                  panelBackground: root.background
                  fontFamily: root.fontFamily
                  fontSize: 13
                  size: 26
                  focusable: true
                  hasCursor: root.focusSection === "panel-action-button" && root.selectedIndex === 3
                  onHovered: function(h) {
                    if (h) { root.focusSection = "panel-action-button"; root.selectedIndex = 3 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                }
              }
            }
          }

          // ---- PanelToolTip ------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "PanelToolTip"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Hover the swatch below to see the styled tooltip. Use this whenever a custom button or row needs a hover hint."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              id: tipSwatch
              width: 140
              height: 36
              readonly property bool focused: root.focusSection === "panel-tool-tip"
              color: tipMouse.containsMouse || focused
                ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.color: focused
                ? Style.focusBorderColor
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
              border.width: focused ? Style.focusBorderWidth : 1
              radius: Style.cornerRadius
              onFocusedChanged: if (focused) root.ensureCursorVisible(this)

              Text {
                anchors.centerIn: parent
                text: "hover me"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: 12
              }

              MouseArea {
                id: tipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) {
                  root.focusSection = "panel-tool-tip"
                  root.selectedIndex = 0
                }
              }

              PanelToolTip {
                visible: tipMouse.containsMouse || tipSwatch.focused
                text: "Styled tooltip — drop into any panel"
                panelForeground: root.foreground
                panelBackground: root.background
                fontFamily: root.fontFamily
              }
            }
          }


          // ---- Slider ------------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Slider"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Volume / progress slider. Drag, click anywhere on the track, or scroll the wheel."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              id: sliderWrapper
              width: parent.width
              implicitHeight: sliderRow.implicitHeight + 24
              readonly property bool focused: root.focusSection === "slider"
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: focused
                ? Style.focusBorderColor
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: focused ? Style.focusBorderWidth : 1
              onFocusedChanged: if (focused) root.ensureCursorVisible(this)

              HoverHandler {
                onHoveredChanged: if (hovered) {
                  root.focusSection = "slider"
                  root.selectedIndex = 0
                }
              }

              Row {
                id: sliderRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                property real demoVolume: 0.45

                Text {
                  text: "󰕾"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 16
                  width: 22
                  horizontalAlignment: Text.AlignHCenter
                  anchors.verticalCenter: parent.verticalCenter
                }

                PanelSlider {
                  id: demoSlider
                  bar: root.fakeBar
                  width: parent.width - 70
                  anchors.verticalCenter: parent.verticalCenter
                  value: sliderRow.demoVolume
                  onMoved: function(v) { sliderRow.demoVolume = v }
                }

                Text {
                  text: Math.round((demoSlider.dragging ? demoSlider.liveValue : sliderRow.demoVolume) * 100) + "%"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  width: 38
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // ---- ChoiceButton --------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "ChoiceButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "A single button in a mutually-exclusive choice group. Selected styling uses the accent fill+border; focus styling uses the Style.focusBorderColor outline so keyboard nav can land on a non-selected option without it reading as the chosen one."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: choiceRow.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: choiceRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                spacing: 6

                Repeater {
                  model: ["top", "right", "bottom", "left"]
                  ChoiceButton {
                    required property string modelData
                    required property int index
                    text: modelData
                    foreground: root.foreground
                    background: root.background
                    accent: root.accent
                    fontFamily: root.fontFamily
                    selected: root.choiceDemoValue === modelData
                    hasCursor: root.focusSection === "choice-button" && root.selectedIndex === index
                    onClicked: {
                      root.focusSection = "choice-button"
                      root.selectedIndex = index
                      root.choiceDemoValue = modelData
                    }
                    onHovered: function(h) {
                      if (h) { root.focusSection = "choice-button"; root.selectedIndex = index }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                }
              }
            }
          }

          // ---- TextField -----------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "TextField"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Single-line input. Inherits Qt Quick Controls TextField, swaps in the kit's focus chrome and selection styling. Toggle `password: true` for masked entry."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: tfCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: tfCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                TextField {
                  id: demoTextField
                  width: parent.width
                  placeholderText: "Type something (Enter to start editing, Esc to leave)"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  hasCursor: !activeFocus && root.focusSection === "text-field" && root.selectedIndex === 0
                  onHoveredChanged: if (hovered) {
                    root.focusSection = "text-field"; root.selectedIndex = 0
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      focus = false
                      event.accepted = true
                    }
                  }
                }

                TextField {
                  id: demoPasswordField
                  width: parent.width
                  password: true
                  placeholderText: "Password"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  hasCursor: !activeFocus && root.focusSection === "text-field" && root.selectedIndex === 1
                  onHoveredChanged: if (hovered) {
                    root.focusSection = "text-field"; root.selectedIndex = 1
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      focus = false
                      event.accepted = true
                    }
                  }
                }
              }
            }
          }

          // ---- NumberField ---------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "NumberField"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Labeled spin box for integer settings. Up/down arrows step the value; the field accepts typed input. Pair with `from`/`to`/`stepSize` to constrain range."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: numberDemo.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              border.width: 1
              radius: Style.cornerRadius

              NumberField {
                id: numberDemo
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 12
                label: "Auto-refresh interval (minutes)"
                from: 1
                to: 1440
                value: root.numberDemoValue
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                hasCursor: root.focusSection === "number-field" && root.selectedIndex === 0
                onModified: function(v) { root.numberDemoValue = v }
                onHovered: function(on) {
                  if (on) { root.focusSection = "number-field"; root.selectedIndex = 0 }
                }
                onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
              }
            }
          }

          // ---- Toggle --------------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Toggle"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Title + description + switch. Click anywhere on the row to flip; caller updates `checked` in response. Same focus tokens as ChoiceButton."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Toggle {
              width: parent.width
              label: "Transparent bar"
              description: "Hide the bar background so the wallpaper shows through."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              checked: root.toggleDemoOn
              hasCursor: root.focusSection === "toggle" && root.selectedIndex === 0
              onHovered: function(h) {
                if (h) { root.focusSection = "toggle"; root.selectedIndex = 0 }
              }
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
              onClicked: {
                root.focusSection = "toggle"; root.selectedIndex = 0
                root.toggleDemoOn = !root.toggleDemoOn
              }
            }

            Toggle {
              width: parent.width
              label: "Square switch (forced)"
              description: "`rounded: false` overrides the theme auto-detect so the switch reads square even when corners are round. Set `rounded: Style.cornerRadius > 0` (the default) to follow the theme."
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              rounded: false
              checked: root.toggleSquareOn
              hasCursor: root.focusSection === "toggle" && root.selectedIndex === 1
              onHovered: function(h) {
                if (h) { root.focusSection = "toggle"; root.selectedIndex = 1 }
              }
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
              onClicked: {
                root.focusSection = "toggle"; root.selectedIndex = 1
                root.toggleSquareOn = !root.toggleSquareOn
              }
            }
          }

          // ---- Dropdown -----------------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Dropdown"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Themed single-select with a panel-styled popup. Tab to focus the trigger, Enter/Space opens, j/k or arrows walk options, Enter selects. Options can be plain strings or { value, label } objects."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: ddCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: ddCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                Dropdown {
                  id: demoDropdown
                  width: 260
                  label: "Center anchor"
                  fontFamily: root.fontFamily
                  options: ["calendar", "weather", "clock", "battery"]
                  value: root.dropdownDemoValue
                  hasCursor: root.focusSection === "dropdown" && root.selectedIndex === 0
                  onHovered: function(h) {
                    if (h) { root.focusSection = "dropdown"; root.selectedIndex = 0 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  onChanged: function(v) { root.dropdownDemoValue = v }
                }
              }
            }
          }

          // ---- SearchableDropdown -------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "SearchableDropdown"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "Dropdown with an embedded filter input. Type to narrow the list, Down to jump from the search to the first match, Enter to select. Use this for the bar settings \"+ Add widget\" picker and any other long-list selector."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: sddCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: sddCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                SearchableDropdown {
                  id: demoSearchableDropdown
                  width: 280
                  label: "Add widget"
                  fontFamily: root.fontFamily
                  placeholderText: "Search widgets..."
                  hasCursor: root.focusSection === "searchable-dropdown" && root.selectedIndex === 0
                  onHovered: function(h) {
                    if (h) { root.focusSection = "searchable-dropdown"; root.selectedIndex = 0 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  options: [
                    { value: "clock", label: "Clock", description: "Time + date display" },
                    { value: "weather", label: "Weather", description: "Local conditions and forecast" },
                    { value: "battery", label: "Battery", description: "Charge level + power profile" },
                    { value: "audio", label: "Audio", description: "Output sink + volume" },
                    { value: "network", label: "Network", description: "Wi-Fi + ethernet status" },
                    { value: "bluetooth", label: "Bluetooth", description: "Paired and nearby devices" },
                    { value: "monitor", label: "Monitor", description: "Brightness + scale" },
                    { value: "calendar", label: "Calendar", description: "Month grid flyout" },
                    { value: "media", label: "Media", description: "Now-playing + transport" },
                    { value: "workspaces", label: "Workspaces", description: "Hyprland workspace pills" },
                    { value: "system-tray", label: "System tray", description: "StatusNotifierItem icons" },
                    { value: "omarchy-menu", label: "Omarchy menu", description: "Launcher / system menu" },
                    { value: "power-profiles", label: "Power profiles", description: "Performance / balanced / saver" },
                    { value: "hardware", label: "Hardware", description: "CPU, GPU, mem utilization" },
                    { value: "notifications", label: "Notifications", description: "Recent notification history" }
                  ]
                  value: root.searchableDemoValue
                  onChanged: function(v) { root.searchableDemoValue = v }
                }
              }
            }
          }

          // ---- Composed example -------------------------------------------
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: "Composed example"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: 13
              font.bold: true
            }
            Text {
              text: "A miniature wifi-style row built from CursorSurface + PanelActionButton + PanelToolTip. This is what new panel rows should look like — no inline Rectangle/Text/MouseArea reimplementation."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: 10
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: composedCol.implicitHeight + 24
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: composedCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 6

                PanelSectionHeader {
                  text: "Wi-Fi networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                CursorSurface {
                  width: parent.width
                  implicitHeight: composedRow.implicitHeight + 12
                  current: true
                  foreground: root.foreground
                  fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  hasCursor: root.focusSection === "composed" && root.selectedIndex === 0
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)

                  HoverHandler {
                    onHoveredChanged: if (hovered) {
                      root.focusSection = "composed"; root.selectedIndex = 0
                    }
                  }

                  Item {
                    id: composedRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    implicitHeight: 36

                    Text {
                      id: composedIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    PanelActionButton {
                      id: composedForget
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰅙"
                      tooltipText: "Forget network"
                      foreground: root.foreground
                      hoverColor: root.urgent
                      panelBackground: root.background
                      fontFamily: root.fontFamily
                    }

                    Column {
                      spacing: 1
                      anchors.left: composedIcon.right
                      anchors.leftMargin: 10
                      anchors.right: composedForget.left
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        text: "HughesWiFi"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        width: parent.width
                      }
                      Text {
                        text: "Connected"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }
                  }
                }

                PanelSeparator { foreground: root.foreground }

                CursorSurface {
                  width: parent.width
                  implicitHeight: idleRow.implicitHeight + 12
                  foreground: root.foreground
                  fill: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                  hasCursor: root.focusSection === "composed" && root.selectedIndex === 1
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)

                  HoverHandler {
                    onHoveredChanged: if (hovered) {
                      root.focusSection = "composed"; root.selectedIndex = 1
                    }
                  }

                  Item {
                    id: idleRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    implicitHeight: 36

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: 14
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: 24
                      anchors.verticalCenter: parent.verticalCenter
                      text: "HughesATT"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: 12
                    }
                  }
                }
              }
            }
          }

          Item { width: 1; height: 12 }
        }
      }
      }
    }
  }
}
