import QtQuick
import QtQuick.Controls as Controls

Item {
  id: root

  property bool showLabel: false
  property var options: []
  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string value: ""
  readonly property bool popupOpen: picker.popup.visible
  signal changed(string value)

  implicitWidth: 180
  implicitHeight: 36
  activeFocusOnTab: true

  function indexForValue() {
    for (var index = 0; index < options.length; ++index)
      if (String(options[index].value) === value) return index
    return options.length > 0 ? 0 : -1
  }

  function close() {
    picker.popup.close()
  }

  function forceActiveFocus(reason) {
    picker.forceActiveFocus(reason === undefined ? Qt.OtherFocusReason : reason)
  }

  Controls.ComboBox {
    id: picker
    anchors.fill: parent
    model: root.options
    textRole: "label"
    currentIndex: root.indexForValue()
    font.family: root.fontFamily
    palette.buttonText: root.foreground
    palette.text: root.foreground
    palette.windowText: root.foreground
    palette.button: root.background
    palette.base: root.background
    palette.highlight: root.accent
    onActivated: function(index) {
      if (index < 0 || index >= root.options.length) return
      root.value = String(root.options[index].value)
      root.changed(root.value)
    }
  }
}
