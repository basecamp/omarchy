import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property var news: null
  property string fontFamily: Style.font.family
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.darker(foreground, 1.55)
  property int editingIndex: -2
  property var selectedUrls: ({})
  property string formError: ""

  readonly property var collections: news ? news.collections : []
  readonly property var sources: news ? news.selectableSources : []
  readonly property bool limitReached: collections.length >= 8 && editingIndex === -1

  signal persistCollections(var collections)

  function copiedCollections() {
    var result = []
    for (var i = 0; i < collections.length; i++) {
      result.push({
        "id": String(collections[i].id || ""),
        "name": String(collections[i].name || ""),
        "sourceUrls": (collections[i].sourceUrls || []).slice()
      })
    }
    return result
  }

  function selectCollection(index) {
    if (index < 0 || index >= collections.length) return
    editingIndex = index
    collectionName.text = String(collections[index].name || "")
    var next = ({})
    var urls = collections[index].sourceUrls || []
    for (var i = 0; i < urls.length; i++) next[String(urls[i] || "")] = true
    selectedUrls = next
    formError = ""
  }

  function newCollection() {
    if (collections.length >= 8) return
    editingIndex = -1
    collectionName.text = ""
    selectedUrls = ({})
    formError = ""
    Qt.callLater(function() { collectionName.forceActiveFocus() })
  }

  function toggleSource(url) {
    var key = String(url || "")
    var next = ({})
    for (var existing in selectedUrls) next[existing] = selectedUrls[existing]
    if (next[key]) delete next[key]
    else next[key] = true
    selectedUrls = next
  }

  function selectedSourceUrls() {
    var result = []
    for (var i = 0; i < sources.length; i++) {
      var url = String(sources[i].url || "")
      if (selectedUrls[url]) result.push(url)
    }
    for (var existing in selectedUrls) {
      if (selectedUrls[existing] && result.indexOf(existing) === -1) result.push(existing)
    }
    return result.slice(0, 21)
  }

  function safeCollectionId(name) {
    var slug = String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").substring(0, 24)
    return (slug || "collection") + "-" + Date.now().toString(36)
  }

  function saveCollection() {
    var name = collectionName.text.replace(/\s+/g, " ").trim()
    var urls = selectedSourceUrls()
    formError = ""
    if (name === "") {
      formError = "Give this collection a name."
      collectionName.forceActiveFocus()
      return
    }
    if (urls.length === 0) {
      formError = "Choose at least one source."
      return
    }
    var next = copiedCollections()
    if (editingIndex >= 0 && editingIndex < next.length) {
      next[editingIndex] = { "id": next[editingIndex].id, "name": name, "sourceUrls": urls }
    } else {
      if (next.length >= 8) return
      next.push({ "id": safeCollectionId(name), "name": name, "sourceUrls": urls })
      editingIndex = next.length - 1
    }
    persistCollections(next)
  }

  function removeCollection(index) {
    var next = copiedCollections()
    if (index < 0 || index >= next.length) return
    next.splice(index, 1)
    persistCollections(next)
    editingIndex = -2
    collectionName.text = ""
    selectedUrls = ({})
    formError = ""
  }

  function activate() {
    if (collections.length > 0) {
      selectCollection(Math.max(0, Math.min(editingIndex, collections.length - 1)))
      Qt.callLater(function() { collectionList.forceActiveFocus() })
    } else {
      newCollection()
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: Style.space(14)

    BorderSurface {
      Layout.preferredWidth: parent.width * 0.34
      Layout.fillHeight: true
      color: "transparent"
      borderSpec: Border.surfaceSpec("rss-collection-list", "border", root.foreground, 1)
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
              text: "COLLECTIONS"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.0
            }
            Text {
              text: "Your focused streams"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.collections.length + " / 8"
            textFormat: Text.PlainText
            color: root.collections.length >= 8 ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Text {
          visible: root.collections.length === 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          text: "No collections yet.\nCreate one to combine sources by topic."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          wrapMode: Text.WordWrap
        }

        ListView {
          id: collectionList
          visible: root.collections.length > 0
          Layout.fillWidth: true
          Layout.fillHeight: true
          model: root.collections
          spacing: Style.space(4)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          activeFocusOnTab: true

          delegate: CursorSurface {
            id: collectionRow
            required property var modelData
            required property int index
            width: collectionList.width
            height: Style.space(46)
            activeFocusOnTab: true
            current: root.editingIndex === index
            hasCursor: activeFocus || collectionMouse.containsMouse
            foreground: root.accent
            Accessible.role: Accessible.ListItem
            Accessible.name: String(modelData.name || "Collection")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(9)
              anchors.rightMargin: Style.space(7)
              spacing: Style.space(8)

              Text {
                text: "󰅩"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.icon
              }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  Layout.fillWidth: true
                  text: String(collectionRow.modelData.name || "Collection")
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: collectionRow.current
                  elide: Text.ElideRight
                }
                Text {
                  text: (collectionRow.modelData.sourceUrls || []).length + " SOURCES"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Keys.onReturnPressed: root.selectCollection(index)
            Keys.onEnterPressed: root.selectCollection(index)

            MouseArea {
              id: collectionMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectCollection(collectionRow.index)
            }
          }
        }

        Button {
          Layout.fillWidth: true
          text: "New collection"
          iconText: "󰐕"
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          focusable: true
          bordered: true
          enabled: root.collections.length < 8
          onClicked: root.newCollection()
        }
      }
    }

    BorderSurface {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: "transparent"
      borderSpec: Border.surfaceSpec("rss-collection-editor", "border", root.foreground, 1)
      radius: Style.cornerRadius

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(10)
        spacing: Style.space(8)

        Text {
          text: root.editingIndex >= 0 ? "EDIT COLLECTION" : "BUILD A COLLECTION"
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.0
        }

        TextField {
          id: collectionName
          Layout.fillWidth: true
          foreground: root.foreground
          accent: root.accent
          placeholderText: "Collection name — e.g. Tech"
          maximumLength: 32
        }

        Text {
          text: "CHOOSE SOURCES"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 0.8
        }

        ListView {
          id: sourceList
          Layout.fillWidth: true
          Layout.fillHeight: true
          model: root.sources
          spacing: Style.space(3)
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: CursorSurface {
            id: sourceRow
            required property var modelData
            width: sourceList.width
            height: Style.space(42)
            activeFocusOnTab: true
            hasCursor: activeFocus || sourceMouse.containsMouse
            current: root.selectedUrls[String(modelData.url || "")] === true
            foreground: root.accent
            Accessible.role: Accessible.CheckBox
            Accessible.name: String(modelData.name || "Source")
            Accessible.checked: current

            Keys.onReturnPressed: root.toggleSource(modelData.url)
            Keys.onEnterPressed: root.toggleSource(modelData.url)
            Keys.onSpacePressed: root.toggleSource(modelData.url)

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(9)
              anchors.rightMargin: Style.space(7)
              spacing: Style.space(8)
              Text {
                Layout.fillWidth: true
                text: String(sourceRow.modelData.name || "Source")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: sourceRow.current
                elide: Text.ElideRight
              }
              ToggleSwitch {
                checked: sourceRow.current
                interactive: false
                cursorRing: false
                foreground: root.foreground
                accent: root.accent
                trackHeight: Style.space(18)
              }
            }

            MouseArea {
              id: sourceMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.toggleSource(sourceRow.modelData.url)
            }
          }
        }

        Text {
          visible: root.formError !== ""
          Layout.fillWidth: true
          text: root.formError
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
            text: root.editingIndex >= 0 ? "Save changes" : "Create collection"
            iconText: "󰄬"
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            focusable: true
            bordered: true
            enabled: !root.limitReached
            onClicked: root.saveCollection()
          }
          Button {
            visible: root.editingIndex >= 0
            text: "Delete"
            foreground: root.urgent
            accent: root.urgent
            fontFamily: root.fontFamily
            focusable: true
            onClicked: root.removeCollection(root.editingIndex)
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.selectedSourceUrls().length + " SELECTED"
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
      }
    }
  }
}
