import QtQuick
import qs.Commons

// Mutually-exclusive row of Buttons — the form-style "pick one of N"
// pattern (bar position top/right/bottom/left, theme preset chips, etc.).
// Emits `changed(value)` when the user activates a different option.
//
// `options` is either a plain string[] (label == value) or an array of
// { value, label, icon?, tooltip? } objects. Mixing is fine.
//
// For panel-cursor-driven selection (where j/k walks a row), use bare
// `Button { hasCursor: ... }` instances in a Row — ButtonGroup is the
// convenience for non-cursor form contexts where you just need
// "selected: value === optionValue" wiring.
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

  signal changed(string value)

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
      text: root.optionLabel(modelData)
      iconText: root.optionIcon(modelData)
      tooltipText: root.optionTooltip(modelData)
      selected: root.optionValue(modelData) === root.value
      foreground: root.foreground
      background: root.background
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: root.fontSize
      focusable: root.focusable
      onClicked: root.changed(root.optionValue(modelData))
    }
  }
}
