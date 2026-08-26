import QtQuick
import QtQuick.Controls
import qs.Commons

// Themed single-select dropdown. Trigger row paints with the kit's focus
// chrome; the popup anchors below and uses Color.popups.background +
// Color.popups.border so it reads as a panel surface rather than the
// platform-native ComboBox look.
//
// `options` accepts either a plain string[] or an array of
// { value, label } objects (label is what we render; value is what we
// emit). Mixing is fine — each row is interpreted independently.
//
// Keyboard: Tab to focus the trigger, Enter/Space opens, Esc closes,
// j/k or Up/Down walks options inside the open popup, Enter selects.
// A sibling SearchableDropdown reuses the same visuals but adds an
// embedded filter input — keep the two separate so each stays simple.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []

  property color foreground: Color.popups.text
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true
  property string popupDirection: "down"  // "down" | "up" | "right" | "left"
  property string popupSideAlignment: "top"  // "top" | "center" | "bottom"
  property int popupAnchorHeight: rowHeight
  property int popupWidth: 0
  property int popupGap: Style.spacing.xxs
  property int popupOffsetX: 0
  // Optional compact trigger that reduces the control to its directional
  // submenu affordance while preserving pointer and keyboard behavior.
  property bool chevronOnly: false
  property bool showChevron: true
  property bool triggerChrome: true

  // Panel-cursor flag. When true, the trigger renders the shared
  // hover-cursor state. Active Qt focus defaults to the same visuals.
  // Emits `hovered(bool)` on pointer enter/leave so the panel can keep
  // its cursor state in sync with the mouse.
  property bool hasCursor: false

  // popupOpen + open()/close()/toggle() let a parent panel know when the
  // dropdown owns keys (its embedded ListView is active) and suspend its
  // own keyCatcher so j/k inside the popup don't double-drive the panel
  // cursor.
  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function currentLabel() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }

  implicitWidth: Style.spacing.dropdownWidth
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
      readonly property var _borderSpec: root.triggerChrome
        ? Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)
        : Border.none()

      color: root.triggerChrome
        ? Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
        : "transparent"
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
        visible: !root.chevronOnly
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.currentLabel()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        visible: root.showChevron
        anchors.right: root.chevronOnly ? undefined : parent.right
        anchors.horizontalCenter: root.chevronOnly ? parent.horizontalCenter : undefined
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: root.chevronOnly ? 0 : trigger.borderRight + Style.spacing.controlGap
        text: root.popupDirection === "right" ? "󰅂"
          : (root.popupDirection === "left" ? "󰅁"
          : (root.popupDirection === "up" ? "󰅃" : "󰅀"))
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        property bool popupWasOpenOnPress: false

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: popupWasOpenOnPress = popup.opened
        onClicked: {
          trigger.forceActiveFocus()
          popupWasOpenOnPress ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup
        popupType: Popup.Item
        property real _anchorWindowX: 0
        property real _anchorWindowY: 0
        readonly property var _windowContent: trigger.Window.window
          ? trigger.Window.window.contentItem : null
        readonly property real _windowWidth: _windowContent ? _windowContent.width : 0
        readonly property real _windowHeight: _windowContent ? _windowContent.height : 0
        readonly property real _edgeMargin: Style.spacing.sm
        readonly property real rowsHeight: root.options.length * root.popupRowHeight
          + Math.max(0, root.options.length - 1) * Style.spacing.labelGap
        readonly property real cappedRowsHeight: root.popupRowHeight * 8
          + 7 * Style.spacing.labelGap
        readonly property real _idealX: (root.popupDirection === "right" ? trigger.width + root.popupGap
          : (root.popupDirection === "left" ? -width - root.popupGap : 0)) + root.popupOffsetX
        readonly property real _idealY: root.popupDirection === "down" ? root.popupAnchorHeight + root.popupGap
          : (root.popupDirection === "up" ? -implicitHeight - root.popupGap
          : (root.popupSideAlignment === "center" ? (root.popupAnchorHeight - implicitHeight) / 2
          : (root.popupSideAlignment === "bottom" ? root.popupAnchorHeight - implicitHeight : 0)))
        x: _windowWidth > 0
          ? Math.max(_edgeMargin - _anchorWindowX,
              Math.min(_windowWidth - _edgeMargin - width - _anchorWindowX, _idealX))
          : _idealX
        y: _windowHeight > 0
          ? Math.max(_edgeMargin - _anchorWindowY,
              Math.min(_windowHeight - _edgeMargin - implicitHeight - _anchorWindowY, _idealY))
          : _idealY
        width: {
          var desired = root.popupWidth > 0 ? root.popupWidth : trigger.width
          return _windowWidth > 0
            ? Math.min(desired, Math.max(0, _windowWidth - 2 * _edgeMargin)) : desired
        }
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        // Include the real insets in the popup height. If the viewport is even
        // a few pixels shorter than its rows, ListView scrolls when keyboard
        // selection reaches the last option and makes the whole menu appear to
        // jump despite every option already fitting on screen.
        implicitHeight: {
          var desired = Math.min(rowsHeight, cappedRowsHeight) + topPadding + bottomPadding
          return _windowHeight > 0
            ? Math.min(desired, Math.max(0, _windowHeight - 2 * _edgeMargin)) : desired
        }
        focus: true
        // A trigger press is handled by the MouseArea above. Keeping it inside
        // the close boundary prevents the default outside-press handler from
        // closing first and making that same click immediately reopen it.
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        function reposition() {
          if (!_windowContent) return
          var point = trigger.mapToItem(_windowContent, 0, 0)
          _anchorWindowX = point.x
          _anchorWindowY = point.y
        }

        onAboutToShow: reposition()
        onOpened: {
          reposition()
          optionList.hoveredIndex = -1
          optionList.pointerActive = false
          // A caller may intentionally preserve a state that is not offered as
          // a menu action. Leave it unhighlighted instead of pretending the
          // first option is selected; Down/j still advances from -1 to row 0.
          optionList.currentIndex = optionList.indexOfValue(root.value)
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          spacing: Style.spacing.labelGap
          property int hoveredIndex: -1
          property bool pointerActive: false
          readonly property int highlightedIndex: pointerActive && hoveredIndex >= 0
            ? hoveredIndex : currentIndex

          HoverHandler {
            onHoveredChanged: if (!hovered) {
              optionList.pointerActive = false
              optionList.hoveredIndex = -1
            }
          }

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
            else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.pointerActive = false
              optionList.hoveredIndex = -1
              optionList.currentIndex = Math.min(root.options.length - 1, optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.pointerActive = false
              optionList.hoveredIndex = -1
              optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              optionList.selectCurrent(); event.accepted = true
            }
          }
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          function indexOfValue(v) {
            for (var i = 0; i < root.options.length; i++)
              if (root.optionValue(root.options[i]) === v) return i
            return -1
          }

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length) return
            var v = root.optionValue(root.options[currentIndex])
            root.changed(v)
            popup.close()
          }

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: optionList.width
            height: root.popupRowHeight
            color: index === optionList.highlightedIndex
              ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.rightMargin: Style.spacing.controlPaddingX
              text: root.optionLabel(modelData)
              color: index === optionList.highlightedIndex
                ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: {
                optionList.pointerActive = true
                optionList.hoveredIndex = parent.index
              }
              onClicked: {
                optionList.currentIndex = parent.index
                optionList.selectCurrent()
              }
            }
          }
        }
      }
    }
  }
}
