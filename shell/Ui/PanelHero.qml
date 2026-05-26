import QtQuick
import qs.Commons

Item {
  id: root

  property Component iconComponent: null
  property string title: ""
  property string meta: ""
  property string detail: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real iconSize: Style.font.display
  property real iconOpacity: 1.0
  property alias metaOpacity: metaText.opacity

  readonly property color dim: Qt.darker(foreground, 1.4)

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconLoader.implicitHeight, heroLabels.implicitHeight)

  Loader {
    id: iconLoader
    sourceComponent: root.iconComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.iconOpacity
  }

  Column {
    id: heroLabels
    anchors.left: iconLoader.right
    anchors.leftMargin: Style.space(14)
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Row {
      id: titleRow
      visible: root.title !== "" || detailPill.visible
      width: parent.width

      Text {
        visible: root.title !== ""
        text: root.title
        width: Math.min(implicitWidth, Math.max(0, parent.width - (detailPill.visible ? detailPill.implicitWidth + Style.space(8) : 0)))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Item {
        width: Math.max(0, parent.width - parent.children[0].width - detailPill.implicitWidth)
        height: 1
      }

      Rectangle {
        id: detailPill
        visible: root.detail !== ""
        implicitWidth: detailText.implicitWidth + Style.space(10)
        implicitHeight: detailText.implicitHeight + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        border.color: Style.normalBorderFor(root.foreground)
        border.width: Style.normalBorderWidth
        radius: Style.cornerRadius

        Text {
          id: detailText
          anchors.centerIn: parent
          text: root.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
    }

    Text {
      id: metaText
      width: parent.width
      text: root.meta.toUpperCase()
      visible: text !== ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
      elide: Text.ElideRight
    }
  }
}
