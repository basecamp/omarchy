import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.news"

  readonly property var news: bar?.shell?.serviceFor("omarchy.news")
  readonly property int unreadCount: news ? news.unreadCount : 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function applySettings() {
    if (news) news.settings = root.settings || ({})
  }

  onNewsChanged: applySettings()
  onSettingsChanged: applySettings()
  Component.onCompleted: applySettings()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.unreadCount > 0
      ? "RSS Reader · " + root.unreadCount + " unread"
      : "RSS Reader"
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
        }

        Rectangle {
          visible: root.unreadCount > 0
          width: Style.space(5)
          height: width
          radius: width / 2
          color: root.urgent
          anchors.right: parent.right
          anchors.top: parent.top
        }
      }
    }
    onPressed: function(buttonCode) {
      if (!root.bar) return
      if (buttonCode === Qt.RightButton) {
        if (root.news) root.news.refresh()
      } else {
        root.bar.run("omarchy-shell shell toggle omarchy.news '{}'")
      }
    }
  }
}
