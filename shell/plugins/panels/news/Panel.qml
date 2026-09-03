import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.news"
  ipcTarget: "omarchy.news"

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property int selectedIndex: 0
  property int visualUnreadCount: 0
  property bool cursorActive: false
  property var currentArticle: null

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var articles: news.visibleItems

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function setCursor(index) {
    cursorActive = true
    selectedIndex = Math.max(0, Math.min(articles.length - 1, index))
    scrollCursorIntoView()
  }

  function moveCursor(dy) {
    if (articles.length === 0) return
    setCursor(selectedIndex + dy)
  }

  function activateCursor() {
    if (articles.length > 0) showArticle(articles[selectedIndex])
  }

  function showArticle(article) {
    if (!article) return
    currentArticle = article
    panelFlick.contentY = 0
    cursorActive = false
  }

  function showHeadlines() {
    currentArticle = null
    panelFlick.contentY = 0
    cursorActive = false
  }

  function scrollArticle(dy) {
    var step = Style.space(72)
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    panelFlick.contentY = Math.max(0, Math.min(maxY, panelFlick.contentY + dy * step))
  }

  function scrollCursorIntoView() {
    if (!articleColumn || selectedIndex < 0 || selectedIndex >= articleColumn.children.length) return
    var item = articleColumn.children[selectedIndex]
    Qt.callLater(function() {
      if (!item) return
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(6)
      var top = point.y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function publishedLabel(value) {
    var date = new Date(String(value || ""))
    if (isNaN(date.getTime())) return ""
    return Qt.formatDate(date, "ddd d MMM")
  }

  function statusLabel() {
    if (news.refreshing && news.items.length === 0) return "CHECKING FOR ANNOUNCEMENTS"
    if (news.stale) return "OFFLINE · SHOWING LAST UPDATE"
    if (news.unreadCount > 0) return news.unreadCount + (news.unreadCount === 1 ? " UNREAD ANNOUNCEMENT" : " UNREAD ANNOUNCEMENTS")
    return "OFFICIAL OMARCHY NEWS"
  }

  onOpenedChanged: if (opened) {
    currentArticle = null
    cursorActive = false
    selectedIndex = 0
    visualUnreadCount = news.unreadCount
    panelFlick.contentY = 0
    news.refresh()
    markReadTimer.restart()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: news
    settings: root.settings
    omarchyPath: root.omarchyPath
  }

  Timer {
    id: markReadTimer
    interval: 1200
    repeat: false
    onTriggered: news.markAllSeen()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: news.unreadCount > 0 ? "Omarchy News · " + news.unreadCount + " unread" : "Omarchy News"
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
          visible: news.unreadCount > 0
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
      if (buttonCode === Qt.RightButton) news.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(root.currentArticle ? readerContent.implicitHeight : listContent.implicitHeight, Style.space(590))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.currentArticle) {
          if (dx < 0) root.showHeadlines()
          else if (dy !== 0) root.scrollArticle(dy)
          return
        }
        if (!root.cursorActive) {
          root.setCursor(0)
          return
        }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx > 0) root.activateCursor()
      }
      onActivateRequested: if (!root.currentArticle && root.cursorActive) root.activateCursor()
      onCloseRequested: {
        if (root.currentArticle) root.showHeadlines()
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.currentArticle) root.showHeadlines()
        else root.switchPanel(direction)
      }
      onTextKey: function(text) {
        if ((text === "b" || text === "B") && root.currentArticle) root.showHeadlines()
        else if (text === "r" || text === "R") news.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.currentArticle ? readerContent.implicitHeight : listContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: listContent
          visible: !root.currentArticle
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Omarchy News"
            meta: root.statusLabel()
            detail: news.unreadCount > 0 ? (news.unreadCount > 9 ? "9+" : String(news.unreadCount)) : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: news.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: news.lastError
            color: news.stale ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: news.items.length > 0
            foreground: root.foreground
          }

          PanelSectionHeader {
            visible: news.items.length > 0
            text: "LATEST"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: news.items.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: news.refreshing ? "Loading the official feed…" : "No announcements available."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Column {
            id: articleColumn
            visible: news.items.length > 0
            width: parent.width
            spacing: Style.space(5)

            Repeater {
              model: root.articles

              ArticleRow {
                required property var modelData
                required property int index
                width: articleColumn.width
                article: modelData
                rowIndex: index
              }
            }
          }
        }

        Column {
          id: readerContent
          visible: !!root.currentArticle
          width: panelFlick.width
          spacing: Style.space(12)

          CursorSurface {
            width: parent.width
            implicitHeight: backLabel.implicitHeight + Style.space(12)
            foreground: root.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showHeadlines()
            }

            RowLayout {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(7)

              Text {
                text: "󰁍"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: backLabel
                Layout.fillWidth: true
                text: "ALL NEWS"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.currentArticle ? String(root.currentArticle.title || "Untitled") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: {
              if (!root.currentArticle) return ""
              var parts = []
              var published = root.publishedLabel(root.currentArticle.published)
              if (published !== "") parts.push(published)
              var author = String(root.currentArticle.author || "")
              if (author !== "") parts.push(author)
              return parts.join(" · ").toUpperCase()
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.currentArticle ? String(root.currentArticle.content || root.currentArticle.summary || "") : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            lineHeight: 1.25
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: "←  Back to all news"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showHeadlines()
            }
          }
        }
      }
    }
  }

  component ArticleRow: CursorSurface {
    id: articleRow
    property var article: null
    property int rowIndex: 0
    readonly property bool unread: rowIndex < root.visualUnreadCount

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    foreground: root.foreground
    implicitHeight: articleContent.implicitHeight + Style.space(16)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(articleRow.rowIndex)
      onClicked: root.showArticle(articleRow.article)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(9)

      Rectangle {
        visible: articleRow.unread
        Layout.preferredWidth: Style.space(5)
        Layout.preferredHeight: Style.space(5)
        radius: width / 2
        color: root.urgent
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(7)
      }

      ColumnLayout {
        id: articleContent
        Layout.fillWidth: true
        spacing: Style.space(3)

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: articleRow.article ? String(articleRow.article.title || "Untitled") : "Untitled"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: articleRow.unread
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: articleRow.article ? String(articleRow.article.summary || "") : ""
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: {
            if (!articleRow.article) return ""
            var parts = []
            var published = root.publishedLabel(articleRow.article.published)
            if (published !== "") parts.push(published)
            var author = String(articleRow.article.author || "")
            if (author !== "") parts.push(author)
            return parts.join(" · ").toUpperCase()
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
          elide: Text.ElideRight
        }
      }

      Text {
        text: "󰁔"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
