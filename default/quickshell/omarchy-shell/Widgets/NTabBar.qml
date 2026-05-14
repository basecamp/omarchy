import QtQuick
import QtQuick.Layouts
import qs.Commons

Rectangle {
  id: root

  property int currentIndex: 0
  property int margins: Style.marginXS
  property bool distributeEvenly: false

  implicitHeight: 32
  radius: Style.radiusS
  color: Color.mSurfaceVariant
  border.color: Color.mOutline
  border.width: Style.borderS

  default property alias content: row.children

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.margins: root.margins
    spacing: Style.marginXS
  }
}
