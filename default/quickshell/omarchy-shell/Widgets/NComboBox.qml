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
  implicitHeight: 32
  leftPadding: 10
  rightPadding: 28
  topPadding: 4
  bottomPadding: 4

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

  contentItem: Text {
    text: root.displayText
    color: Color.mOnSurface
    font: root.font
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }

  background: Rectangle {
    color: Color.mSurfaceVariant
    border.color: root.activeFocus ? Color.mPrimary : Color.mOutline
    border.width: Style.borderS
    radius: 0
  }

  indicator: Text {
    x: root.width - width - 10
    y: (root.height - height) / 2
    text: "▾"
    color: Color.mOnSurfaceVariant
    font.family: root.font.family
    font.pixelSize: 11
  }

  delegate: ItemDelegate {
    id: del
    required property int index
    required property var modelData
    width: ListView.view ? ListView.view.width : root.width
    height: 28
    highlighted: root.highlightedIndex === del.index

    contentItem: Text {
      text: {
        var m = del.modelData
        if (m === null || m === undefined) return ""
        if (root.textRole && m[root.textRole] !== undefined) return String(m[root.textRole])
        return String(m)
      }
      color: Color.mOnSurface
      font: root.font
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    background: Rectangle {
      color: del.highlighted || del.hovered
        ? Qt.rgba(Color.mOnSurface.r, Color.mOnSurface.g, Color.mOnSurface.b, 0.14)
        : "transparent"
      radius: 0
    }
  }

  popup: Popup {
    y: root.height
    width: root.width
    implicitHeight: Math.min(contentItem.implicitHeight + 2, 280)
    padding: 1

    background: Rectangle {
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Style.borderS
      radius: 0
    }

    contentItem: ListView {
      clip: true
      implicitHeight: contentHeight
      model: root.popup.visible ? root.delegateModel : null
      currentIndex: root.highlightedIndex
      boundsBehavior: Flickable.StopAtBounds
      ScrollIndicator.vertical: ScrollIndicator { }
    }
  }
}
