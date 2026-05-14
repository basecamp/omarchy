import QtQuick
import QtQuick.Controls
import qs.Commons

ComboBox {
  id: root

  property string label: ""
  // Noctalia's NComboBox API commonly uses a model of { key, name } objects,
  // a currentKey property, and an onSelected(key, item) handler. Qt's ComboBox
  // only knows currentIndex/currentText, so bridge the small API surface here.
  property string currentKey: ""

  signal selected(var key, var item)

  textRole: "name"
  valueRole: "key"
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: Style.fontSizeS

  function itemAt(index) {
    if (index < 0) return null
    if (Array.isArray(root.model)) return root.model[index] || null
    return null
  }

  function keyAt(index) {
    var item = itemAt(index)
    if (!item) return ""
    if (item.key !== undefined && item.key !== null) return String(item.key)
    if (item.value !== undefined && item.value !== null) return String(item.value)
    if (item.name !== undefined && item.name !== null) return String(item.name)
    return String(item)
  }

  function syncCurrentIndex() {
    if (!Array.isArray(root.model)) return
    for (var i = 0; i < root.model.length; i++) {
      if (keyAt(i) === String(root.currentKey || "")) {
        if (root.currentIndex !== i) root.currentIndex = i
        return
      }
    }
    if (root.model.length > 0 && root.currentIndex < 0) root.currentIndex = 0
  }

  Component.onCompleted: syncCurrentIndex()
  onCurrentKeyChanged: syncCurrentIndex()
  onModelChanged: syncCurrentIndex()

  onActivated: function(index) {
    var item = itemAt(index)
    var key = keyAt(index)
    root.currentKey = key
    root.selected(key, item)
  }

  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: Color.mOutline
    border.width: Style.borderS
    radius: Style.radiusS
  }
}
