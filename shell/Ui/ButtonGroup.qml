import QtQuick
import qs.Commons

// Mutually-exclusive row of Buttons — the form-style "pick one of N"
// pattern (bar position top/right/bottom/left, theme preset chips, etc.).
// Emits `changed(value)` when the user activates a different option.
//
// `options` is either a plain string[] (label == value) or an array of
// { value, label, icon?, tooltip? } objects. Mixing is fine.
//
// Panels with their own keyboard cursor model bind `cursorIndex` to the
// currently-focused option (-1 = no cursor) and listen on `hovered` to
// keep that state synced with the mouse. Forms that don't care about
// the panel cursor model can leave both alone.
Row {
  id: root

  property var options: []
  property string value: ""
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property bool focusable: false

  // -1 disables the cursor highlight (the form case). Set from a panel
  // to drive Button.hasCursor on the matching index.
  property int cursorIndex: -1

  signal changed(string value)
  signal hovered(int index, bool isHovered)

  spacing: 6

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object" && o.label !== undefined) ? String(o.label) : String(o)
  }
  function optionIcon(o) {
    return (o && typeof o === "object" && o.icon) ? String(o.icon) : ""
  }
  function optionTooltip(o) {
    return (o && typeof o === "object" && o.tooltip) ? String(o.tooltip) : ""
  }

  Repeater {
    model: root.options

    delegate: Button {
      required property var modelData
      required property int index
      text: root.optionLabel(modelData)
      iconText: root.optionIcon(modelData)
      tooltipText: root.optionTooltip(modelData)
      selected: root.optionValue(modelData) === root.value
      hasCursor: root.cursorIndex === index
      // Every chip carries an idle border so the group reads as a row of
      // distinct options. selected paints accent; the cursor recolors the
      // chip's border to accent via Button's bordered+hot path.
      bordered: true
      foreground: root.foreground
      background: root.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      focusable: root.focusable
      onClicked: root.changed(root.optionValue(modelData))
      onHovered: function(h) { root.hovered(index, h) }
    }
  }
}
