import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property var news: null
  property var shell: null
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property int editingIndex: -1
  property string formError: ""
  property var pendingPersistSettings: null
  property bool showingCollections: false

  readonly property var catalog: news ? news.feedCatalog : []
  readonly property var enabledFeedIds: news ? news.enabledFeedIds : []
  readonly property var customEntries: news ? news.customFeedEntries : []
  readonly property bool customLimitReached: customEntries.length >= 10 && editingIndex < 0

  signal done()

  function categoryColor(category) {
    var value = String(category || "custom")
    if (value === "developer") return Color.cyan
    if (value === "startup") return Color.yellow
    if (value === "technology") return Color.blue
    if (value === "linux") return Color.green
    if (value === "ai") return Color.magenta
    return Color.muted
  }

  function persistSettings(values) {
    if (!news) return
    var next = ({})
    var current = news.settings || ({})
    for (var key in current) if (key !== "id") next[key] = current[key]
    for (var update in values) next[update] = values[update]
    news.settings = next
    pendingPersistSettings = next
    settingsPersistTimer.restart()
  }

  function flushSettings() {
    if (!pendingPersistSettings) return
    var next = pendingPersistSettings
    pendingPersistSettings = null
    if (shell && typeof shell.updateEntryInline === "function")
      shell.updateEntryInline("omarchy.news", next)
  }

  function toggleCurated(sourceId) {
    var enabled = []
    for (var i = 0; i < enabledFeedIds.length; i++) enabled.push(String(enabledFeedIds[i]))
    var index = enabled.indexOf(String(sourceId))
    if (index >= 0) enabled.splice(index, 1)
    else enabled.push(String(sourceId))

    var ordered = []
    for (var catalogIndex = 0; catalogIndex < catalog.length; catalogIndex++) {
      var candidate = String(catalog[catalogIndex].id || "")
      if (enabled.indexOf(candidate) >= 0) ordered.push(candidate)
    }
    persistSettings({ "enabledFeeds": ordered })
  }

  function copiedEntries() {
    var result = []
    for (var i = 0; i < customEntries.length; i++) {
      result.push({
        "name": String(customEntries[i].name || "").trim(),
        "url": String(customEntries[i].url || "").trim()
      })
    }
    return result
  }

  function serialiseEntries(entries) {
    var result = []
    for (var i = 0; i < entries.length; i++) {
      var name = String(entries[i].name || "").trim()
      var url = String(entries[i].url || "").trim()
      result.push(name === "" ? url : name + "|" + url)
    }
    return result.join("; ")
  }

  function canonicalCustomUrl(value) {
    var match = String(value || "").trim().match(/^https:\/\/([^\s/@:]+)(?::443)?((?:[/?#][^\s]*)?)$/i)
    if (!match) return ""
    var host = String(match[1] || "").toLowerCase()
    if (host === "localhost" || /(?:^|\.)localhost$/.test(host) || /\.local$/.test(host)) return ""
    if (/^\d+(?:\.\d+){3}$/.test(host)) return ""
    return "https://" + host + String(match[2] || "").replace(/#.*$/, "")
  }

  function persistCustomEntries(entries) {
    persistSettings({ "customFeeds": serialiseEntries(entries) })
  }

  function collectionsAfterSourceChange(oldUrl, newUrl) {
    var groups = news ? news.collections : []
    var result = []
    for (var i = 0; i < groups.length; i++) {
      var urls = []
      var sourceUrls = groups[i].sourceUrls || []
      for (var sourceIndex = 0; sourceIndex < sourceUrls.length; sourceIndex++) {
        var url = String(sourceUrls[sourceIndex] || "")
        if (url === oldUrl) url = newUrl
        if (url !== "" && urls.indexOf(url) === -1) urls.push(url)
      }
      if (urls.length > 0) {
        result.push({
          "id": String(groups[i].id || ""),
          "name": String(groups[i].name || ""),
          "sourceUrls": urls
        })
      }
    }
    return result
  }

  function editCustom(index) {
    if (index < 0 || index >= customEntries.length) return
    editingIndex = index
    customName.text = String(customEntries[index].name || "")
    customUrl.text = String(customEntries[index].url || "")
    formError = ""
    Qt.callLater(function() { customName.forceActiveFocus() })
  }

  function cancelEdit() {
    editingIndex = -1
    customName.text = ""
    customUrl.text = ""
    formError = ""
  }

  function removeCustom(index) {
    var entries = copiedEntries()
    if (index < 0 || index >= entries.length) return
    var removedUrl = String(entries[index].url || "")
    entries.splice(index, 1)
    persistSettings({
      "customFeeds": serialiseEntries(entries),
      "feedCollections": JSON.stringify(collectionsAfterSourceChange(removedUrl, ""))
    })
    if (editingIndex === index) cancelEdit()
    else if (editingIndex > index) editingIndex--
  }

  function moveCustom(index, direction) {
    var entries = copiedEntries()
    var target = index + direction
    if (index < 0 || index >= entries.length || target < 0 || target >= entries.length) return
    var moved = entries[index]
    entries[index] = entries[target]
    entries[target] = moved
    persistCustomEntries(entries)
    if (editingIndex === index) editingIndex = target
    else if (editingIndex === target) editingIndex = index
  }

  function saveCustom() {
    if (!news || customLimitReached) return
    var name = customName.text.trim()
    var url = customUrl.text.trim()
    formError = ""
    if (url === "") {
      formError = "Paste an HTTPS RSS URL first."
      customUrl.forceActiveFocus()
      return
    }
    if (name.indexOf("|") >= 0 || name.indexOf(";") >= 0 || url.indexOf(";") >= 0) {
      formError = "Names and URLs cannot contain | or ; characters."
      return
    }
    var canonicalUrl = canonicalCustomUrl(url)
    if (canonicalUrl === "") {
      formError = "Feed must be a public HTTPS URL."
      return
    }
    var entries = copiedEntries()
    for (var i = 0; i < entries.length; i++) {
      if (i !== editingIndex && entries[i].url === canonicalUrl) {
        formError = "That feed is already on your shelf."
        return
      }
    }
    var safeName = name
    var entry = { "name": safeName, "url": canonicalUrl }
    if (editingIndex >= 0 && editingIndex < entries.length) {
      var previousUrl = String(entries[editingIndex].url || "")
      entries[editingIndex] = entry
      persistSettings({
        "customFeeds": serialiseEntries(entries),
        "feedCollections": JSON.stringify(collectionsAfterSourceChange(previousUrl, canonicalUrl))
      })
    } else {
      entries.push(entry)
      persistCustomEntries(entries)
    }
    cancelEdit()
  }

  function sourceState(url) {
    if (!news) return null
    for (var i = 0; i < news.sources.length; i++) {
      if (String(news.sources[i].url || "") === String(url || "")) return news.sources[i]
    }
    return null
  }

  function sourceStatus(url) {
    var state = sourceState(url)
    if (!state) return news && news.refreshing ? "CHECKING" : "WAITING"
    if (String(state.error || "") !== "") return state.stale === true ? "CACHED" : "ERROR"
    return "LIVE"
  }

  function sourceStatusColor(url) {
    var status = sourceStatus(url)
    if (status === "ERROR") return urgent
    if (status === "LIVE") return Color.green
    return dim
  }

  function sourceName(entry) {
    var state = sourceState(entry ? entry.url : "")
    if (state && state.name) return String(state.name)
    return String((entry && (entry.name || entry.url)) || "Custom feed")
  }

  function activate() {
    Qt.callLater(function() {
      if (root.showingCollections) collectionManager.activate()
      else if (catalogList.count > 0) catalogList.currentItem.forceActiveFocus()
      else customUrl.forceActiveFocus()
    })
  }

  function toggleManagerPage() {
    showingCollections = !showingCollections
    activate()
  }

  onVisibleChanged: if (!visible) flushSettings()
  Component.onDestruction: flushSettings()

  Timer {
    id: settingsPersistTimer
    interval: 150
    repeat: false
    onTriggered: root.flushSettings()
  }

  Keys.onEscapePressed: {
    flushSettings()
    root.done()
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.space(12)

    BorderSurface {
      Layout.fillWidth: true
      implicitHeight: pinnedRow.implicitHeight + Style.space(20)
      color: Style.selectedFillFor(root.foreground, root.accent)
      borderSpec: Border.controlSpec("selected", root.foreground, root.accent)
      radius: Style.cornerRadius

      RowLayout {
        id: pinnedRow
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(10)

        Text {
          text: root.showingCollections ? "󰅩" : "󰐃"
          textFormat: Text.PlainText
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.iconLarge
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(1)

          Text {
            text: root.showingCollections ? "COLLECTIONS" : "OMARCHY"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            font.letterSpacing: 0.8
          }

          Text {
            text: root.showingCollections
              ? "Combine sources into focused streams without another fetch."
              : "Official announcements are always pinned to your feed."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Button {
          text: root.showingCollections ? "Sources" : "Collections"
          iconText: root.showingCollections ? "󰒍" : "󰅩"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          focusable: true
          bordered: true
          onClicked: root.toggleManagerPage()
        }

        Text {
          text: root.showingCollections ? "8 MAX" : "PINNED"
          textFormat: Text.PlainText
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }
      }
    }

    RowLayout {
      visible: !root.showingCollections
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(14)

      BorderSurface {
        Layout.preferredWidth: parent.width * 0.48
        Layout.fillHeight: true
        color: "transparent"
        borderSpec: Border.surfaceSpec("news-feed-manager-catalog", "border", root.foreground, 1)
        radius: Style.cornerRadius

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(8)

          RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
              spacing: Style.space(1)
              Text {
                text: "CURATED SOURCES"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
              Text {
                text: "Choose what belongs in your news stream."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Item { Layout.fillWidth: true }

            Text {
              text: root.enabledFeedIds.length + " ON"
              textFormat: Text.PlainText
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          ListView {
            id: catalogList
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.catalog
            spacing: Style.space(3)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: CursorSurface {
              id: catalogRow
              required property var modelData
              width: catalogList.width
              height: Style.space(45)
              activeFocusOnTab: true
              hasCursor: activeFocus || catalogMouse.containsMouse
              current: root.enabledFeedIds.indexOf(String(modelData.id || "")) >= 0
              foreground: root.categoryColor(modelData.category)
              Accessible.role: Accessible.CheckBox
              Accessible.name: String(modelData.name || "")
              Accessible.checked: current

              Keys.onReturnPressed: root.toggleCurated(modelData.id)
              Keys.onEnterPressed: root.toggleCurated(modelData.id)
              Keys.onSpacePressed: root.toggleCurated(modelData.id)

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(9)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                Rectangle {
                  width: Style.space(4)
                  height: Style.space(26)
                  radius: width / 2
                  color: root.categoryColor(catalogRow.modelData.category)
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  Text {
                    text: String(catalogRow.modelData.name || "")
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: catalogRow.current
                  }
                  Text {
                    Layout.fillWidth: true
                    text: String(catalogRow.modelData.description || "")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                ToggleSwitch {
                  checked: catalogRow.current
                  interactive: false
                  cursorRing: false
                  foreground: root.foreground
                  accent: root.categoryColor(catalogRow.modelData.category)
                  trackHeight: Style.space(18)
                }
              }

              MouseArea {
                id: catalogMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  catalogRow.forceActiveFocus()
                  root.toggleCurated(catalogRow.modelData.id)
                }
              }
            }
          }
        }
      }

      BorderSurface {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: "transparent"
        borderSpec: Border.surfaceSpec("news-feed-manager-custom", "border", root.foreground, 1)
        radius: Style.cornerRadius

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(8)

          RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
              spacing: Style.space(1)
              Text {
                text: "YOUR SOURCES"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
              }
              Text {
                text: "Add any public HTTPS RSS feed."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Item { Layout.fillWidth: true }
            Text {
              text: root.customEntries.length + " / 10"
              textFormat: Text.PlainText
              color: root.customLimitReached ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }

          Text {
            visible: root.customEntries.length === 0
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(82)
            text: "No custom feeds yet.\nPaste one below to add it to the source rail."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
          }

          ListView {
            id: customList
            visible: root.customEntries.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, Style.space(190))
            model: root.customEntries
            spacing: Style.space(4)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: BorderSurface {
              id: customRow
              required property var modelData
              required property int index
              width: customList.width
              height: Style.space(55)
              color: root.editingIndex === index
                ? Style.selectedFillFor(root.foreground, root.accent)
                : "transparent"
              borderSpec: Border.controlSpec(root.editingIndex === index ? "selected" : "normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(4)
                spacing: Style.space(4)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 0
                  RowLayout {
                    Layout.fillWidth: true
                    Text {
                      Layout.fillWidth: true
                      text: root.sourceName(customRow.modelData)
                      textFormat: Text.PlainText
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                      elide: Text.ElideRight
                    }
                    Text {
                      text: root.sourceStatus(customRow.modelData.url)
                      textFormat: Text.PlainText
                      color: root.sourceStatusColor(customRow.modelData.url)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                  Text {
                    Layout.fillWidth: true
                    text: String(customRow.modelData.url || "")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideMiddle
                  }
                }

                PanelActionButton {
                  iconText: "󰁝"
                  tooltipText: "Move up"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  enabled: customRow.index > 0
                  onClicked: root.moveCustom(customRow.index, -1)
                }
                PanelActionButton {
                  iconText: "󰁅"
                  tooltipText: "Move down"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  enabled: customRow.index < root.customEntries.length - 1
                  onClicked: root.moveCustom(customRow.index, 1)
                }
                PanelActionButton {
                  iconText: "󰏫"
                  tooltipText: "Edit feed"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  focusable: true
                  onClicked: root.editCustom(customRow.index)
                }
                PanelActionButton {
                  iconText: "󰆴"
                  tooltipText: "Remove feed"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  focusable: true
                  onClicked: root.removeCustom(customRow.index)
                }
              }
            }
          }

          PanelSeparator {
            Layout.fillWidth: true
            foreground: root.foreground
          }

          Text {
            text: root.editingIndex >= 0 ? "EDIT SUBSCRIPTION" : "ADD SUBSCRIPTION"
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }

          TextField {
            id: customName
            Layout.fillWidth: true
            foreground: root.foreground
            accent: root.accent
            placeholderText: "Name (optional)"
            maximumLength: 48
            onAccepted: customUrl.forceActiveFocus()
          }

          TextField {
            id: customUrl
            Layout.fillWidth: true
            foreground: root.foreground
            accent: root.accent
            placeholderText: "https://example.com/feed.xml"
            maximumLength: 2048
            onAccepted: root.saveCustom()
          }

          Text {
            visible: root.formError !== "" || root.customLimitReached
            Layout.fillWidth: true
            text: root.customLimitReached ? "Remove a feed before adding another." : root.formError
            textFormat: Text.PlainText
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(6)

            Button {
              text: root.editingIndex >= 0 ? "Save feed" : "Add feed"
              iconText: "󰐕"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: true
              bordered: true
              enabled: !root.customLimitReached
              onClicked: root.saveCustom()
            }

            Button {
              visible: root.editingIndex >= 0
              text: "Cancel"
              foreground: root.dim
              accent: root.accent
              fontFamily: root.fontFamily
              focusable: true
              onClicked: root.cancelEdit()
            }

            Item { Layout.fillWidth: true }

            Text {
              text: "Esc returns to Reader"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }

    CollectionManager {
      id: collectionManager
      visible: root.showingCollections
      Layout.fillWidth: true
      Layout.fillHeight: true
      news: root.news
      fontFamily: root.fontFamily
      foreground: root.foreground
      accent: root.accent
      urgent: root.urgent
      dim: root.dim
      onPersistCollections: function(collections) {
        root.persistSettings({ "feedCollections": JSON.stringify(collections) })
      }
    }
  }
}
