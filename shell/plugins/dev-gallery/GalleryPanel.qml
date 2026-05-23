import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Visual reference + live playground for omarchy-shell's common UI
// components. Summon with `omarchy dev ui-preview`, or directly via:
//   omarchy-shell shell summon omarchy.dev-gallery "{}"
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

    // Optional { section: "button" } in the payload lets `omarchy dev
    // ui-preview <section>` open the gallery with the cursor already on
    // a specific component, so iterating on one widget doesn't require
    // scrolling from the top each time. Unknown section names are
    // ignored — the gallery opens at its default position.
    var requested = ""
    if (payloadJson) {
      try {
        var parsed = JSON.parse(String(payloadJson))
        if (parsed && typeof parsed.section === "string") requested = parsed.section
      } catch (e) { /* ignore */ }
    }

    // Defer the section assignment + focus so the FloatingWindow's
    // content tree is mounted. The hasCursor bindings on each demo
    // target then scroll themselves into view via onHasCursorChanged.
    Qt.callLater(function() {
      if (requested && visibleSections.indexOf(requested) !== -1) {
        focusSection = requested
        selectedIndex = sectionFirstIndex(requested)
      }
      if (keyCatcher) keyCatcher.forceActiveFocus()
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
  property var shell: null

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

  // Demo state mutated by interaction.
  property string choiceDemoValue: "top"
  property bool toggleDemoOn: true
  property bool toggleSquareOn: false
  property string dropdownDemoValue: "Clock"
  property string searchableDemoValue: ""
  property int numberDemoValue: 15

  readonly property var visibleSections: [
    "cursor-surface", "button", "button-group", "panel-action-button",
    "panel-tool-tip", "slider", "text-field", "number-field",
    "toggle", "dropdown", "searchable-dropdown", "composed"
  ]

  function sectionCount(section) {
    switch (section) {
      case "cursor-surface":      return 3
      case "button":              return 5
      case "button-group":        return 4
      case "panel-action-button": return 4
      case "panel-tool-tip":      return 1
      case "slider":              return 1
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
  // buttons) — j/k jumps to the next/prev section, h/l walks within the row.
  function sectionIsHorizontal(section) {
    return section === "button"
      || section === "button-group"
      || section === "panel-action-button"
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
    if (focusSection === "button-group") {
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
          anchors.margins: Style.space(18)
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          width: scrollArea.availableWidth
          spacing: Style.space(22)

          // ---- Header ------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(4)

            Text {
              text: "Omarchy shell · dev gallery"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              font.bold: true
            }
            Text {
              text: "Live previews of every type exported from qs.Ui. Use this as the visual reference when porting panels or building plugins. j/k or arrows to walk; h/l within rows; Enter to activate; Esc to close."
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              wrapMode: Text.WordWrap
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- Kit conventions ---------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Conventions"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Rectangle {
              width: parent.width
              implicitHeight: conventionsCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: conventionsCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: "Theme. qs.Commons.Style exposes cornerRadius plus shared normal / hover-cursor / selected / focus state tokens (state colors, fill alphas, border widths, and border alphas), spacing tokens, typography, and bar dimensions. Focus defaults to hover-cursor; selected borders are off by default. Border widths are the theme-level on/off switch for state borders. qs.Commons.Color exposes foreground / background / accent / urgent plus per-surface roles. Components default-bind to these so a caller with no overrides matches the active theme."
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: "Single cursor. Most reusable panel primitives expose hasCursor: bool and emit hovered(bool); composed rows (including sliders) wrap their content in CursorSurface. The panel root owns cursorActive + focusSection + selectedIndex; each element binds hasCursor: root.cursorActive && root.focusSection === 'X' && root.selectedIndex === N, and onHovered flips cursorActive on while updating the same state. No initial highlight, then one highlight on screen once the keyboard or mouse enters. See plugins/audio/BarWidget.qml for the canonical recipe."
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: "Popups + editors. Dropdown / SearchableDropdown expose popupOpen plus open() / close() / toggle(); inline TextField uses activeFocus. While any of those own the keys, set PanelKeyCatcher.blocked so the panel's cursor model freezes and the active widget handles input."
                }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: "Adding a component. Drop the QML in Ui/, add a line to Ui/qmldir, then add a section here using the real type (not a copy). The gallery doubles as a smoke test — if a component starts misbehaving this is the fastest place to see it."
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- Typography --------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Typography"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Style.font.* is the shell-wide type scale. Themes ship a single "
                + "[font] base-size in shell.toml; every token derives from it via a "
                + "fixed multiplier, so changing base-size rescales the whole shell "
                + "proportionally. There is no upper clamp. Themes can also pin "
                + "individual tokens (caption, heading, display, etc.) for stylistic "
                + "emphasis. The family follows the fontconfig monospace alias \u2014 "
                + "set it with `omarchy font set <name>`."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: typeCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: typeCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(10)

                Text {
                  text: "Scale"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                // Every Style.font.* token rendered at its actual size. The
                // model is data, not a Component graph, so this list stays
                // in lockstep with the singleton without manual upkeep.
                Repeater {
                  model: [
                    { key: "caption",      size: Style.font.caption,      sample: "Section header text" },
                    { key: "bodySmall",    size: Style.font.bodySmall,    sample: "Secondary / tooltip text" },
                    { key: "body",         size: Style.font.body,         sample: "Default label and control text" },
                    { key: "subtitle",     size: Style.font.subtitle,     sample: "Row title text" },
                    { key: "title",        size: Style.font.title,        sample: "Card title text" },
                    { key: "heading",      size: Style.font.heading,      sample: "Panel heading" },
                    { key: "display",      size: Style.font.display,      sample: "Display text" },
                    { key: "displayLarge", size: Style.font.displayLarge, sample: "Display large" },
                    { key: "iconSmall",    size: Style.font.iconSmall,    sample: "\uf004 \uf005 \uf02d" },
                    { key: "icon",         size: Style.font.icon,         sample: "\uf004 \uf005 \uf02d" },
                    { key: "iconLarge",    size: Style.font.iconLarge,    sample: "\uf004 \uf005 \uf02d" }
                  ]
                  delegate: Item {
                    required property var modelData
                    width: typeCol.width
                    implicitHeight: Math.max(metaCol.implicitHeight, sampleText.implicitHeight)

                    Column {
                      id: metaCol
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(140)
                      spacing: Style.space(1)
                      Text {
                        text: "Style.font." + modelData.key
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                      Text {
                        text: modelData.size + " px"
                        color: Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      id: sampleText
                      anchors.left: metaCol.right
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(16)
                      text: modelData.sample
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: modelData.size
                      elide: Text.ElideRight
                    }
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
                }

                Text {
                  text: "Theme tokens"
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Grid {
                  columns: 2
                  columnSpacing: Style.space(16)
                  rowSpacing: Style.space(4)
                  width: parent.width

                  Text {
                    text: "Style.font.family"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.font.family
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.font.resolvedFamily"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.font.resolvedFamily
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.font.baseSize"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.font.baseSize + " px"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.bar.sizeHorizontal"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.bar.sizeHorizontal + " px"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.bar.sizeVertical"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.bar.sizeVertical + " px"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.spacing.scale"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.spacing.scale.toFixed(2)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Text {
                    text: "Style.spacing.panelPadding"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                  Text {
                    text: Style.spacing.panelPadding + " px"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- PanelSectionHeader ------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "PanelSectionHeader"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Small-caps-style intro label for a section."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              width: parent.width
              implicitHeight: shCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: shCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(6)

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
                  fontSize: Style.font.bodySmall
                }
              }
            }
          }

          // ---- PanelSeparator ----------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "PanelSeparator"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "1px horizontal rule. Default 0.12 alpha on foreground; tweak via strength."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Rectangle {
              width: parent.width
              implicitHeight: sepCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: sepCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(12)

                PanelSeparator { foreground: root.foreground }
                PanelSeparator { foreground: root.foreground; strength: 0.25 }
                PanelSeparator { foreground: root.foreground; strength: 0.45 }
              }
            }
          }

          // ---- CursorSurface -----------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "CursorSurface"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Single highlight chrome for keyboard+mouse navigable items. Press h/l (anywhere in this window) to move the demo cursor. The middle item is also marked `current` to show how the two states layer."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: csCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: csCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(6)

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
                    implicitHeight: csLabel.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.focusSection === "cursor-surface" && root.selectedIndex === index
                    current: index === 1
                    foreground: root.foreground
                    fill: Style.hoverFillFor(root.foreground, root.accent)
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)

                    Text {
                      id: csLabel
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
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

          // ---- Button ------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Button"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "The kit's only button. State flags compose from shared tokens: hasCursor / hover paints the hover-cursor fill; active/selected add the selected fill; selected borders are off by default; bordered opts into normal/hover-cursor borders; focusable uses the same defaults as hover-cursor. Click below or press h/l to walk the demo cursor."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: buttonRow.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: buttonRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                spacing: Style.space(16)

                // Each demo Button is paired with a caption labeling the
                // state(s) it exercises so the section reads as one Button
                // showing its flag combinations side by side.

                Column {
                  spacing: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DHCP"
                    tooltipText: "Use DNS from DHCP"
                    hasCursor: root.focusSection === "button" && root.selectedIndex === 0
                    onHovered: function(h) {
                      if (h) { root.focusSection = "button"; root.selectedIndex = 0 }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "idle"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  spacing: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Cloudflare"
                    tooltipText: "Set DNS to Cloudflare"
                    active: true
                    hasCursor: root.focusSection === "button" && root.selectedIndex === 1
                    onHovered: function(h) {
                      if (h) { root.focusSection = "button"; root.selectedIndex = 1 }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "active"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  spacing: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconText: "󰑐"
                    tooltipText: "Refresh"
                    horizontalPadding: Style.spacing.controlGap
                    verticalPadding: Style.spacing.labelGap
                    hasCursor: root.focusSection === "button" && root.selectedIndex === 2
                    onHovered: function(h) {
                      if (h) { root.focusSection = "button"; root.selectedIndex = 2 }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "icon only"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  spacing: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    iconText: "󰂯"
                    text: "On"
                    tooltipText: "Turn Bluetooth off"
                    active: true
                    hasCursor: root.focusSection === "button" && root.selectedIndex === 3
                    onHovered: function(h) {
                      if (h) { root.focusSection = "button"; root.selectedIndex = 3 }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "icon + active"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Column {
                  spacing: Style.space(6)
                  Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Apply"
                    focusable: true
                    bordered: true
                    hasCursor: root.focusSection === "button" && root.selectedIndex === 4
                    onHovered: function(h) {
                      if (h) { root.focusSection = "button"; root.selectedIndex = 4 }
                    }
                    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "bordered + focusable"
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- ButtonGroup -------------------------------------------------
          Column {
            id: buttonGroupSection
            width: parent.width
            spacing: Style.space(8)
            readonly property bool focused: root.focusSection === "button-group"
            onFocusedChanged: if (focused) root.ensureCursorVisible(this)

            Text {
              text: "ButtonGroup"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Mutually-exclusive row of Buttons. Each chip uses Button's bordered chrome; selected and cursor states come from the same shared Style tokens as every other control. Click to pick or press h/l + Enter."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: choiceRow.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              ButtonGroup {
                id: choiceRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                options: ["top", "right", "bottom", "left"]
                value: root.choiceDemoValue
                cursorIndex: root.focusSection === "button-group" ? root.selectedIndex : -1
                onChanged: function(v) {
                  root.focusSection = "button-group"
                  root.choiceDemoValue = v
                }
                onHovered: function(index, isHovered) {
                  if (isHovered) {
                    root.focusSection = "button-group"
                    root.selectedIndex = index
                  }
                }
              }
            }
          }

          // ---- PanelActionButton -------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "PanelActionButton"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "22×22 right-edge action button. Two flavors via hoverColor: default (foreground tint, e.g. confirm) and urgent (red tint, e.g. forget/unpair). Hover and click states are intrinsic; the row that owns it stays responsible for the cursor highlight."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: pabCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Row {
                id: pabCol
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                spacing: Style.space(18)

                PanelActionButton {
                  iconText: "󰄬"
                  tooltipText: "Confirm (default flavor)"
                  foreground: root.foreground
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
                  fontFamily: root.fontFamily
                  fontSize: Style.font.subtitle
                  size: Style.space(26)
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
            spacing: Style.space(8)

            Text {
              text: "PanelToolTip"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Hover the swatch below to see the styled tooltip. Use this whenever a custom button or row needs a hover hint."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              id: tipSwatch
              width: Style.space(140)
              height: Style.space(36)
              readonly property bool focused: root.focusSection === "panel-tool-tip"
              color: tipMouse.containsMouse || focused
                ? Style.hoverFillFor(root.foreground, root.accent)
                : Style.normalFillFor(root.foreground, root.accent)
              border.color: focused
                ? Style.hoverBorderFor(root.foreground, root.accent)
                : Style.normalBorderFor(root.foreground, root.accent)
              border.width: focused ? Style.hoverBorderWidth : Style.normalBorderWidth
              radius: Style.cornerRadius
              onFocusedChanged: if (focused) root.ensureCursorVisible(this)

              Text {
                anchors.centerIn: parent
                text: "hover me"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
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
                fontFamily: root.fontFamily
              }
            }
          }


          // ---- Slider ------------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "Slider"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Volume / progress slider. Drag, click anywhere on the track, or scroll the wheel."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            CursorSurface {
              id: sliderWrapper
              width: parent.width
              implicitHeight: sliderRow.implicitHeight + Style.spacing.rowPaddingX * 2
              outline: true
              foreground: root.foreground
              hasCursor: root.focusSection === "slider"
              onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)

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
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(10)
                property real demoVolume: 0.45

                Text {
                  text: "󰕾"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
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
                  font.pixelSize: Style.font.body
                  width: 38
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // ---- TextField -----------------------------------------------------
          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "TextField"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Single-line input. Inherits Qt Quick Controls TextField, swaps in the kit's focus chrome and selection styling. Toggle `password: true` for masked entry."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: tfCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: tfCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(10)

                TextField {
                  id: demoTextField
                  width: parent.width
                  placeholderText: "Type something (Enter to start editing, Esc to leave)"
                  foreground: root.foreground
                  accent: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
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
                  font.pixelSize: Style.font.body
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
            spacing: Style.space(8)

            Text {
              text: "NumberField"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Labeled spin box for integer settings. Up/down arrows step the value; the field accepts typed input. Pair with `from`/`to`/`stepSize` to constrain range."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: numberDemo.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
              border.width: 1
              radius: Style.cornerRadius

              NumberField {
                id: numberDemo
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
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
            spacing: Style.space(8)

            Text {
              text: "Toggle"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Title + description + switch. Click anywhere on the row to flip; caller updates `checked` in response. Uses the same normal / hover-cursor / focus tokens as Button and the checked switch track uses selected tokens."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
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
            spacing: Style.space(8)

            Text {
              text: "Dropdown"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Themed single-select with a panel-styled popup. Tab to focus the trigger, Enter/Space opens, j/k or arrows walk options, Enter selects. Options can be plain strings or { value, label } objects."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: ddCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: ddCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(6)

                Dropdown {
                  id: demoDropdown
                  width: Style.spacing.dropdownWidth
                  label: "Center anchor"
                  fontFamily: root.fontFamily
                  options: ["omarchy.clock", "omarchy.weather", "omarchy.power"]
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
            spacing: Style.space(8)

            Text {
              text: "SearchableDropdown"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "Dropdown with an embedded filter input. Type to narrow the list, Down to jump from the search to the first match, Enter to select. Use this for the bar settings \"+ Add widget\" picker and any other long-list selector."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: sddCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: sddCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(6)

                SearchableDropdown {
                  id: demoSearchableDropdown
                  width: Style.spacing.searchableDropdownWidth
                  label: "Add widget"
                  fontFamily: root.fontFamily
                  placeholderText: "Search widgets..."
                  hasCursor: root.focusSection === "searchable-dropdown" && root.selectedIndex === 0
                  onHovered: function(h) {
                    if (h) { root.focusSection = "searchable-dropdown"; root.selectedIndex = 0 }
                  }
                  onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(this)
                  options: [
                    { value: "Clock", label: "Clock", description: "Time + date display" },
                    { value: "Weather", label: "Weather", description: "Local conditions and forecast" },
                    { value: "omarchy.power", label: "Power", description: "Charge level + power profile" },
                    { value: "audio", label: "Audio", description: "Output sink + volume" },
                    { value: "network", label: "Network", description: "Wi-Fi + ethernet status" },
                    { value: "bluetooth", label: "Bluetooth", description: "Paired and nearby devices" },
                    { value: "monitor", label: "Monitor", description: "Brightness + scale" },
                    { value: "Media", label: "Media", description: "Now-playing + transport" },
                    { value: "Workspaces", label: "Workspaces", description: "Hyprland workspace pills" },
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
            spacing: Style.space(8)

            Text {
              text: "Composed example"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: "A miniature wifi-style row built from CursorSurface + PanelActionButton + PanelToolTip. This is what new panel rows should look like — no inline Rectangle/Text/MouseArea reimplementation."
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              width: parent.width
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: parent.width
              implicitHeight: composedCol.implicitHeight + Style.spacing.rowPaddingX * 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
              radius: Style.cornerRadius
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
              border.width: 1

              Column {
                id: composedCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(14)
                spacing: Style.space(6)

                PanelSectionHeader {
                  text: "Wi-Fi networks"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                CursorSurface {
                  width: parent.width
                  implicitHeight: composedRow.implicitHeight + Style.spacing.md * 2
                  current: true
                  foreground: root.foreground
                  fill: Style.hoverFillFor(root.foreground, root.accent)
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
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    implicitHeight: 36

                    Text {
                      id: composedIcon
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }

                    PanelActionButton {
                      id: composedForget
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      iconText: "󰅙"
                      tooltipText: "Forget network"
                      foreground: root.foreground
                      hoverColor: root.urgent
                      fontFamily: root.fontFamily
                    }

                    Column {
                      spacing: Style.space(1)
                      anchors.left: composedIcon.right
                      anchors.leftMargin: Style.space(10)
                      anchors.right: composedForget.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        text: "HughesWiFi"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                        width: parent.width
                      }
                      Text {
                        text: "Connected"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                        width: parent.width
                      }
                    }
                  }
                }

                PanelSeparator { foreground: root.foreground }

                CursorSurface {
                  width: parent.width
                  implicitHeight: idleRow.implicitHeight + Style.spacing.md * 2
                  foreground: root.foreground
                  fill: Style.hoverFillFor(root.foreground, root.accent)
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
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    implicitHeight: 36

                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: "󰖩"
                      color: Qt.darker(root.foreground, 1.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                    }

                    Text {
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(24)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "HughesATT"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }
          }

          Item { width: 1; height: Style.spacing.rowPaddingX }
        }
      }
      }
    }
  }
}
