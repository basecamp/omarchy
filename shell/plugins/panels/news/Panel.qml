import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property int selectedIndex: 0
  property string selectedSourceId: "all"
  property string focusArea: "headlines"
  property var currentArticle: null
  property bool managingFeeds: false

  readonly property var news: service
  readonly property var articles: news ? news.itemsForSource(selectedSourceId) : []
  readonly property var sourceFilters: news
    ? [{ "id": "all", "name": "All", "category": "all" }].concat(news.collectionFilters).concat(news.visibleSources)
    : []
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    window.visible = true
    focusArea = "headlines"
    selectedIndex = Math.max(0, Math.min(selectedIndex, articles.length - 1))
    if (!currentArticle && articles.length > 0) currentArticle = articles[selectedIndex]
    if (news && news.items.length === 0 && !news.refreshing) news.refresh(true)
    markReadTimer.restart()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    markReadTimer.stop()
    closingFromHost = true
    opened = false
    window.visible = false
    closingFromHost = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide("omarchy.news")
    else close()
  }

  function openFeedManager() {
    markReadTimer.stop()
    managingFeeds = true
    focusArea = "manager"
    feedManager.activate()
  }

  function closeFeedManager() {
    managingFeeds = false
    markReadTimer.restart()
    focusArea = "headlines"
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function openCurrentArticle() {
    if (!currentArticle) return
    var url = String(currentArticle.url || "")
    if (!/^https?:\/\//.test(url)) return
    Qt.openUrlExternally(url)
  }

  function selectArticle(index, readIt) {
    if (articles.length === 0) return
    selectedIndex = Math.max(0, Math.min(articles.length - 1, index))
    currentArticle = articles[selectedIndex]
    headlineList.positionViewAtIndex(selectedIndex, ListView.Contain)
    if (readIt) {
      focusArea = "article"
      articleFlick.contentY = 0
    }
  }

  function moveHeadline(dy) {
    selectArticle(selectedIndex + dy, false)
  }

  function selectSource(sourceId) {
    selectedSourceId = String(sourceId || "all")
    for (var i = 0; i < sourceFilters.length; i++) {
      if (String(sourceFilters[i].id || "") === selectedSourceId) {
        sourceRail.positionViewAtIndex(i, ListView.Contain)
        break
      }
    }
    selectedIndex = 0
    currentArticle = articles.length > 0 ? articles[0] : null
    headlineList.positionViewAtBeginning()
    articleFlick.contentY = 0
    focusArea = "headlines"
  }

  function cycleSource(direction) {
    if (sourceFilters.length < 2) return
    var current = 0
    for (var i = 0; i < sourceFilters.length; i++) {
      if (String(sourceFilters[i].id || "") === selectedSourceId) { current = i; break }
    }
    var next = (current + direction + sourceFilters.length) % sourceFilters.length
    selectSource(sourceFilters[next].id)
  }

  function scrollArticle(dy) {
    var step = Style.space(80)
    var maxY = Math.max(0, articleFlick.contentHeight - articleFlick.height)
    articleFlick.contentY = Math.max(0, Math.min(maxY, articleFlick.contentY + dy * step))
  }

  function publishedLabel(value) {
    var date = new Date(String(value || ""))
    if (isNaN(date.getTime())) return ""
    return Qt.formatDate(date, "ddd d MMM yyyy")
  }

  function categoryColor(category) {
    var value = String(category || "custom")
    if (value === "official") return Color.accent
    if (value === "developer") return Color.cyan
    if (value === "startup") return Color.yellow
    if (value === "technology") return Color.blue
    if (value === "linux") return Color.green
    if (value === "ai") return Color.magenta
    if (value === "collection") return Color.accent
    if (value === "all") return root.foreground
    return Color.muted
  }

  function categoryLabel(category) {
    var value = String(category || "custom")
    if (value === "official") return "Official"
    if (value === "developer") return "Developer"
    if (value === "startup") return "Startups"
    if (value === "technology") return "Technology"
    if (value === "linux") return "Linux"
    if (value === "ai") return "AI"
    if (value === "collection") return "Collection"
    return "Custom"
  }

  function statusLabel() {
    if (!news) return "LOADING NEWS SERVICE"
    if (news.refreshing && news.items.length === 0) return "CHECKING FOR NEWS"
    if (news.configurationError !== "") return "CHECK CUSTOM FEED SETTINGS"
    if (news.partial) return "SOME SOURCES COULD NOT REFRESH"
    if (news.stale) return "OFFLINE · SHOWING LAST UPDATE"
    if (news.unreadCount > 0) {
      if (news.sources.length > 1) return news.unreadCount + (news.unreadCount === 1 ? " UNREAD STORY" : " UNREAD STORIES")
      return news.unreadCount + (news.unreadCount === 1 ? " UNREAD ANNOUNCEMENT" : " UNREAD ANNOUNCEMENTS")
    }
    if (news.sources.length > 1) return news.sources.length + " NEWS SOURCES"
    return "OFFICIAL OMARCHY NEWS"
  }

  onArticlesChanged: {
    if (articles.length === 0) {
      currentArticle = null
      selectedIndex = 0
      return
    }
    var currentId = currentArticle ? String(currentArticle.id || "") : ""
    for (var i = 0; i < articles.length; i++) {
      if (String(articles[i].id || "") === currentId) {
        selectedIndex = i
        // Keep the reading snapshot stable until the user selects again.
        return
      }
    }
    selectedIndex = 0
    currentArticle = articles[0]
  }

  onSourceFiltersChanged: {
    var found = selectedSourceId === "all"
    for (var i = 0; i < sourceFilters.length; i++) {
      if (String(sourceFilters[i].id || "") === selectedSourceId) { found = true; break }
    }
    if (!found) selectSource("all")
  }

  readonly property string currentArticleId: currentArticle ? String(currentArticle.id || "") : ""
  onCurrentArticleIdChanged: {
    articleFlick.contentY = 0
    markReadTimer.restart()
  }

  Timer {
    id: markReadTimer
    interval: 1200
    repeat: false
    onTriggered: if (root.opened && !root.managingFeeds && root.news && focusScope.activeFocus) root.news.markArticleSeen(root.currentArticle)
  }

  FloatingWindow {
    id: window
    title: "RSS Reader"
    color: root.background
    implicitWidth: 1040
    implicitHeight: 720
    minimumSize: Qt.size(720, 480)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("omarchy.news")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      onActiveFocusChanged: {
        if (activeFocus) markReadTimer.restart()
        else markReadTimer.stop()
      }

      // Feed-manager controls can retain active focus after the manager is
      // hidden. Handle reader navigation before those child controls so a
      // stale ListView focus cannot swallow Up/Down. While the manager is
      // visible, leave every key except Escape to its fields and controls.
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.managingFeeds) {
          if (event.key === Qt.Key_Escape) {
            root.closeFeedManager()
            event.accepted = true
          }
          return
        }
        if ((openOriginalButton.activeFocus || manageButton.activeFocus || refreshButton.activeFocus || closeButton.activeFocus)
            && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) return
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_F) {
          root.openFeedManager()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          if (root.news) root.news.refresh()
          event.accepted = true
        } else if (event.key === Qt.Key_O) {
          root.openCurrentArticle()
          event.accepted = true
        } else if (event.key === Qt.Key_BracketLeft) {
          root.cycleSource(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_BracketRight) {
          root.cycleSource(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.focusArea = "headlines"
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (root.articles.length > 0) root.selectArticle(root.selectedIndex, true)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          if (root.focusArea === "article") root.scrollArticle(-1)
          else root.moveHeadline(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          if (root.focusArea === "article") root.scrollArticle(1)
          else root.moveHeadline(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.focusArea = "article"
          root.scrollArticle(-4)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_Space) {
          root.focusArea = "article"
          root.scrollArticle(4)
          event.accepted = true
        } else if (event.key === Qt.Key_Home && root.focusArea === "article") {
          articleFlick.contentY = 0
          event.accepted = true
        } else if (event.key === Qt.Key_End && root.focusArea === "article") {
          articleFlick.contentY = Math.max(0, articleFlick.contentHeight - articleFlick.height)
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(18)
        spacing: Style.space(14)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          ColumnLayout {
            spacing: Style.space(2)

            Text {
              text: "RSS READER"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              font.bold: true
              font.letterSpacing: 1.2
            }

            Text {
              textFormat: Text.PlainText
              text: root.managingFeeds ? "CHOOSE WHAT BELONGS IN YOUR FEED" : root.statusLabel()
              color: root.news && (root.news.stale || root.news.partial) ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.8
            }
          }

          Item {
            Layout.fillWidth: true
          }

          PanelActionButton {
            id: manageButton
            focusable: true
            iconText: root.managingFeeds ? "󰅖" : "󰒓"
            tooltipText: root.managingFeeds ? "Return to Reader (Esc)" : "Manage feeds (F)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              if (root.managingFeeds) root.closeFeedManager()
              else root.openFeedManager()
            }
          }

          PanelActionButton {
            id: refreshButton
            focusable: true
            iconText: "󰑐"
            tooltipText: "Refresh news (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.news && !root.news.refreshing
            onClicked: if (root.news) root.news.refresh()
          }

          PanelActionButton {
            id: closeButton
            focusable: true
            iconText: "󰅖"
            tooltipText: "Close (Esc)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.dismiss()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        FeedManager {
          id: feedManager
          visible: root.managingFeeds
          Layout.fillWidth: true
          Layout.fillHeight: true
          news: root.news
          shell: root.shell
          fontFamily: root.fontFamily
          foreground: root.foreground
          accent: root.accent
          urgent: root.urgent
          onDone: root.closeFeedManager()
        }

        RowLayout {
          visible: !root.managingFeeds
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(16)

          BorderSurface {
            id: feedPane
            Layout.preferredWidth: Math.min(Style.space(340), window.width * 0.38)
            Layout.fillHeight: true
            color: root.focusArea === "headlines" ? Style.focusFillFor(root.foreground, root.accent) : "transparent"
            borderSpec: root.focusArea === "headlines"
              ? Border.controlSpec("focus", root.foreground, root.accent)
              : Border.surfaceSpec("news-list", "border", root.foreground, 1)
            radius: Style.cornerRadius

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "BROWSE FEED"
                  color: root.focusArea === "headlines" ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.0
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: root.focusArea === "headlines" ? "↑↓ SELECT  ·  → READ" : "← RETURN"
                  color: root.focusArea === "headlines" ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                }
              }

              ListView {
                id: sourceRail
                visible: root.sourceFilters.length > 1
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? Style.space(30) : 0
                orientation: ListView.Horizontal
                spacing: Style.space(5)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.sourceFilters

                delegate: CursorSurface {
                  id: sourceChip
                  required property var modelData
                  width: sourceLabel.implicitWidth + Style.space(18)
                  height: sourceRail.height
                  current: String(modelData.id || "") === root.selectedSourceId
                  hasCursor: current && root.focusArea === "headlines"
                  foreground: root.categoryColor(modelData.category)

                  Text {
                    id: sourceLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: String(sourceChip.modelData.name || "Source").toUpperCase()
                    color: sourceChip.current
                      ? root.categoryColor(sourceChip.modelData.category)
                      : Util.alpha(root.categoryColor(sourceChip.modelData.category), 0.68)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: sourceChip.current
                    font.letterSpacing: 0.6
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectSource(sourceChip.modelData.id)
                  }
                }
              }

              ListView {
                id: headlineList
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.articles
                spacing: Style.space(5)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: CursorSurface {
                  id: headline
                  required property var modelData
                  required property int index
                  width: headlineList.width
                  implicitHeight: headlineText.implicitHeight + headlineMeta.implicitHeight + Style.space(22)
                  hasCursor: root.focusArea === "headlines" && index === root.selectedIndex
                  current: root.currentArticle && String(root.currentArticle.id || "") === String(modelData.id || "")
                  foreground: root.foreground

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                      root.focusArea = "headlines"
                      root.selectArticle(headline.index, false)
                    }
                    onClicked: root.selectArticle(headline.index, true)
                  }

                  Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Style.space(10)
                    spacing: Style.space(5)

                    Text {
                      id: headlineText
                      width: parent.width
                      textFormat: Text.PlainText
                      text: String(headline.modelData.title || "Untitled")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      id: headlineMeta
                      width: parent.width
                      textFormat: Text.PlainText
                      text: {
                        var parts = []
                        if (root.selectedSourceId === "all") parts.push(String(headline.modelData.sourceName || ""))
                        var published = root.publishedLabel(headline.modelData.published)
                        if (published !== "") parts.push(published)
                        return parts.join(" · ").toUpperCase()
                      }
                      color: root.categoryColor(headline.modelData.sourceCategory)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          BorderSurface {
            id: storyPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: root.focusArea === "article" ? Style.focusFillFor(root.foreground, root.accent) : "transparent"
            borderSpec: root.focusArea === "article"
              ? Border.controlSpec("focus", root.foreground, root.accent)
              : Border.surfaceSpec("news-story", "border", root.foreground, 1)
            radius: Style.cornerRadius

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(8)

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(8)

                Text {
                  text: "READ STORY"
                  color: root.focusArea === "article" ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.0
                }

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: root.focusArea === "article" ? "↑↓ SCROLL  ·  ← FEED" : "→ START READING"
                  color: root.focusArea === "article" ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignRight
                }
              }

              Flickable {
                id: articleFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: articleColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                  id: articleColumn
                  width: articleFlick.width - Style.space(12)
                  spacing: Style.space(14)

                Text {
                  visible: !root.currentArticle
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.news && root.news.refreshing ? "Fetching the latest news…" : "No announcements available for this source."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: !!root.currentArticle
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.currentArticle ? String(root.currentArticle.title || "Untitled") : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                RowLayout {
                  visible: !!root.currentArticle
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: {
                      if (!root.currentArticle) return ""
                      var parts = []
                      var sourceName = String(root.currentArticle.sourceName || "")
                      if (sourceName !== "") parts.push(sourceName)
                      parts.push(root.categoryLabel(root.currentArticle.sourceCategory))
                      var published = root.publishedLabel(root.currentArticle.published)
                      if (published !== "") parts.push(published)
                      var author = String(root.currentArticle.author || "")
                      if (author !== "") parts.push(author)
                      return parts.join(" · ").toUpperCase()
                    }
                    color: root.categoryColor(root.currentArticle ? root.currentArticle.sourceCategory : "custom")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.8
                    elide: Text.ElideRight
                  }

                  Button {
                    id: openOriginalButton
                    text: "OPEN ORIGINAL"
                    iconText: "󰏌"
                    tooltipText: "Open the full article (O)"
                    foreground: root.foreground
                    accent: root.categoryColor(root.currentArticle ? root.currentArticle.sourceCategory : "custom")
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    iconSize: Style.font.bodySmall
                    horizontalPadding: Style.space(7)
                    verticalPadding: Style.space(3)
                    bordered: true
                    focusable: true
                    onClicked: root.openCurrentArticle()
                  }
                }

                PanelSeparator {
                  visible: !!root.currentArticle
                  width: parent.width
                  foreground: root.foreground
                }

                Text {
                  id: articleBody
                  visible: !!root.currentArticle
                  width: parent.width
                  textFormat: root.currentArticle && root.currentArticle.contentHtml ? Text.StyledText : Text.PlainText
                  text: root.currentArticle
                    ? String(root.currentArticle.contentHtml || root.currentArticle.content || root.currentArticle.summary || "")
                    : ""
                  color: root.foreground
                  linkColor: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  lineHeight: 1.35
                  wrapMode: Text.WordWrap
                  onLinkActivated: function(link) { Qt.openUrlExternally(link) }

                  HoverHandler {
                    cursorShape: articleBody.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                  }
                }

                  Text {
                    visible: !!root.currentArticle
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.sourceFilters.length > 1
                      ? "[ / ] switch source  ·  O original  ·  R refresh  ·  Esc close"
                      : "O original  ·  R refresh  ·  Esc close"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }
              }

              MouseArea {
                anchors.fill: articleFlick
                acceptedButtons: Qt.NoButton
                onWheel: function(wheel) {
                  root.focusArea = "article"
                  wheel.accepted = false
                }
              }
            }
          }
        }
      }
    }
  }
}
