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
  property int sectionIndex: 0
  property int itemIndex: 0
  property string focusArea: "items"

  readonly property var github: service
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color muted: Color.muted
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family
  readonly property bool compactMode: window.width < 980
  readonly property var sections: [
    { "id": "inbox", "label": "INBOX", "key": "1", "glyph": "󰇮" },
    { "id": "issues", "label": "ISSUES", "key": "2", "glyph": "󰅩" },
    { "id": "pulls", "label": "PULL REQUESTS", "key": "3", "glyph": "󰘬" },
    { "id": "discussions", "label": "DISCUSSIONS", "key": "4", "glyph": "󰍩" },
    { "id": "ci", "label": "CI", "key": "5", "glyph": "󰗡" }
  ]
  readonly property var currentItems: itemsForSection(sectionIndex)
  readonly property var currentItem: currentItems.length > 0
    ? currentItems[Math.max(0, Math.min(itemIndex, currentItems.length - 1))]
    : null

  function open(payloadJson) {
    closingFromHost = false
    opened = true
    window.visible = true
    if (github) github.refresh()
    ensureSelection()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    closingFromHost = true
    opened = false
    window.visible = false
    closingFromHost = false
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide("omarchy.github")
    else close()
  }

  function itemsForSection(index) {
    if (!github) return []
    if (index === 0) return github.notifications
    if (index === 1) return github.issues
    if (index === 2) return github.pullRequests
    if (index === 3) return github.discussions
    return github.ci
  }

  function countForSection(index) {
    return itemsForSection(index).length
  }

  function sectionNeedsAttention(index) {
    if (!github) return false
    if (index === 0) return github.notifications.length > 0
    if (index === 1) return github.issues.length > 0
    if (index === 2) return github.reviewRequestCount > 0
    if (index === 4) return github.failingCiCount > 0
    return false
  }

  function ensureSelection() {
    sectionIndex = Math.max(0, Math.min(sections.length - 1, sectionIndex))
    itemIndex = Math.max(0, Math.min(currentItems.length - 1, itemIndex))
  }

  function selectSection(index) {
    sectionIndex = Math.max(0, Math.min(sections.length - 1, index))
    itemIndex = 0
    focusArea = "items"
    itemList.positionViewAtBeginning()
  }

  function moveSection(delta) {
    selectSection((sectionIndex + delta + sections.length) % sections.length)
  }

  function moveItem(delta) {
    if (currentItems.length === 0) return
    itemIndex = Math.max(0, Math.min(currentItems.length - 1, itemIndex + delta))
    itemList.positionViewAtIndex(itemIndex, ListView.Contain)
  }

  function openCurrentItem() {
    if (!currentItem) return
    openWebUrl(currentItem.url)
  }

  function openWebUrl(value) {
    var url = String(value || "")
    if (!/^https:\/\/github\.com\//.test(url)) return
    Qt.openUrlExternally(url)
  }

  function relativeTime(value) {
    var date = new Date(String(value || ""))
    if (isNaN(date.getTime())) return ""
    var seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000))
    if (seconds < 60) return "NOW"
    if (seconds < 3600) return Math.floor(seconds / 60) + "M"
    if (seconds < 86400) return Math.floor(seconds / 3600) + "H"
    if (seconds < 604800) return Math.floor(seconds / 86400) + "D"
    return Qt.formatDate(date, "d MMM")
  }

  function stateColor(state) {
    var value = String(state || "UNKNOWN")
    if (value === "FAILURE" || value === "ERROR") return urgent
    if (value === "PENDING" || value === "EXPECTED") return accent
    if (value === "SUCCESS") return foreground
    return muted
  }

  function stateLabel(item) {
    if (!item) return ""
    if (item.kind === "ci") {
      if (item.state === "SUCCESS") return "PASSING"
      if (item.state === "FAILURE" || item.state === "ERROR") return "FAILING"
      if (item.state === "PENDING" || item.state === "EXPECTED") return "RUNNING"
      return "NO CHECKS"
    }
    if (item.kind === "pull-request") {
      if (item.draft) return "DRAFT"
      if (item.lane === "Review requested") return "REVIEW REQUESTED"
      if (item.reviewDecision) return String(item.reviewDecision).replace(/_/g, " ")
      return String(item.state || "OPEN")
    }
    if (item.kind === "discussion") return item.comments + (item.comments === 1 ? " REPLY" : " REPLIES")
    return String(item.lane || "OPEN").toUpperCase()
  }

  function statusLine() {
    if (!github) return "STARTING GITHUB SERVICE"
    if (github.refreshing && github.viewer === "") return "CONNECTING THROUGH GH"
    if (github.lastError !== "" && github.stale) return "OFFLINE · SHOWING LAST UPDATE"
    if (github.lastError !== "") return github.lastError.toUpperCase()
    if (github.partial) return "PARTIAL DATA · CHECK GH PERMISSIONS"
    if (github.attentionCount > 0) return github.attentionCount + " ATTENTION SIGNALS"
    return "NOTHING WAITING ON YOU"
  }

  function emptyTitle() {
    if (github && github.refreshing) return "Checking GitHub…"
    if (sectionIndex === 0) return "Inbox zero"
    if (sectionIndex === 1) return "No assigned issues"
    if (sectionIndex === 2) return "No open pull requests"
    if (sectionIndex === 3) return "No recent discussions"
    return "No repositories with CI"
  }

  function emptyBody() {
    if (github && github.refreshing) return "Fresh activity will appear here as it arrives."
    if (github && github.errorKind === "missing-gh") return "Install GitHub CLI, then refresh this panel."
    if (github && github.errorKind === "auth") return "Run gh auth login in a terminal, then press R."
    if (github && github.errorKind === "permission") return "Run gh auth refresh -h github.com -s notifications, then press R."
    if (sectionIndex === 3) return "Discussions are collected from your most recently active repositories."
    if (sectionIndex === 4) return "The latest default-branch rollup appears for each active repository."
    return "There is no matching work in this view."
  }

  onCurrentItemsChanged: ensureSelection()

  FloatingWindow {
    id: window
    title: "Omarchy GitHub"
    color: root.background
    implicitWidth: 1180
    implicitHeight: 760
    minimumSize: Qt.size(820, 520)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("omarchy.github")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          if (root.github) root.github.refresh()
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
          root.selectSection(event.key - Qt.Key_1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
          root.moveSection(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
          root.moveSection(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.moveItem(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.moveItem(1)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.moveItem(-6)
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.moveItem(6)
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_O) {
          root.openCurrentItem()
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
              text: "GITHUB"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.iconLarge
              font.bold: true
              font.letterSpacing: 1.4
            }

            Text {
              textFormat: Text.PlainText
              text: root.github && root.github.viewer ? "@" + root.github.viewer.toUpperCase() + "  ·  " + root.statusLine() : root.statusLine()
              color: root.github && (root.github.lastError !== "" || root.github.partial) ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 0.7
              elide: Text.ElideRight
              Layout.maximumWidth: window.width - Style.space(160)
            }
          }

          Item { Layout.fillWidth: true }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: "Refresh GitHub (R)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.github && !root.github.refreshing
            onClicked: if (root.github) root.github.refresh()
          }

          PanelActionButton {
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

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.space(14)

          Rectangle {
            Layout.preferredWidth: root.compactMode ? 174 : 190
            Layout.fillHeight: true
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
            radius: Style.cornerRadius

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Text {
                text: "ATTENTION"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                Layout.leftMargin: Style.space(8)
                Layout.topMargin: Style.space(6)
                Layout.bottomMargin: Style.space(5)
              }

              Repeater {
                model: root.sections

                delegate: Rectangle {
                  required property int index
                  required property var modelData
                  Layout.fillWidth: true
                  Layout.preferredHeight: Style.space(48)
                  radius: Style.cornerRadius
                  color: navMouse.pressed
                    ? Style.pressedFillFor(root.foreground, root.accent)
                    : (index === root.sectionIndex
                      ? Style.selectedFillFor(root.foreground, root.accent)
                      : (navMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"))
                  Accessible.role: Accessible.Button
                  Accessible.name: modelData.label + ", " + root.countForSection(index) + " items"
                  Accessible.selected: index === root.sectionIndex
                  Accessible.onPressAction: root.selectSection(index)

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(10)
                    spacing: Style.space(8)

                    Rectangle {
                      Layout.preferredWidth: 3
                      Layout.preferredHeight: Style.space(24)
                      radius: 2
                      color: root.sectionNeedsAttention(index) ? root.urgent : (index === root.sectionIndex ? root.accent : root.muted)
                      opacity: root.sectionNeedsAttention(index) || index === root.sectionIndex ? 1 : 0.35
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.glyph
                      color: index === root.sectionIndex ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.label
                      color: index === root.sectionIndex ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 0.45
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: root.countForSection(index)
                      visible: root.countForSection(index) > 0
                      color: root.sectionNeedsAttention(index) ? root.urgent : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.key
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectSection(index)
                  }
                }
              }

              Item { Layout.fillHeight: true }

              Text {
                text: "← → SWITCH\n↑ ↓ SELECT\nENTER OPEN"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.5
                lineHeight: 1.35
                Layout.leftMargin: Style.space(8)
                Layout.bottomMargin: Style.space(6)
              }
            }
          }

          Rectangle {
            Layout.preferredWidth: 410
            Layout.fillWidth: root.compactMode
            Layout.fillHeight: true
            color: "transparent"

            ListView {
              id: itemList
              anchors.fill: parent
              clip: true
              spacing: Style.space(6)
              model: root.currentItems
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                required property int index
                required property var modelData
                width: itemList.width
                height: Style.space(82)
                radius: Style.cornerRadius
                color: itemMouse.pressed
                  ? Style.pressedFillFor(root.foreground, root.accent)
                  : (index === root.itemIndex
                    ? Style.selectedFillFor(root.foreground, root.accent)
                    : (itemMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"))
                Accessible.role: Accessible.ListItem
                Accessible.name: String(modelData.repo || "") + ", " + String(modelData.title || "Untitled") + ", " + root.stateLabel(modelData)
                Accessible.selected: index === root.itemIndex
                Accessible.onPressAction: {
                  root.itemIndex = index
                  root.openCurrentItem()
                }

                ColumnLayout {
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(4)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      text: String(modelData.repo || "")
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: root.relativeTime(modelData.updatedAt)
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(modelData.title || "Untitled")
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: index === root.itemIndex
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    Layout.fillWidth: true
                  }

                  RowLayout {
                    Layout.fillWidth: true

                    Text {
                      textFormat: Text.PlainText
                      text: root.stateLabel(modelData)
                      color: modelData.state ? root.stateColor(modelData.state) : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 0.4
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.number ? "#" + modelData.number : ""
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }

                MouseArea {
                  id: itemMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.itemIndex = index
                  onDoubleClicked: {
                    root.itemIndex = index
                    root.openCurrentItem()
                  }
                }
              }

              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            ColumnLayout {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(340))
              spacing: Style.space(10)
              visible: root.currentItems.length === 0

              Text {
                textFormat: Text.PlainText
                text: root.emptyTitle()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }

              Text {
                textFormat: Text.PlainText
                text: root.emptyBody()
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.compactMode
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)
            radius: Style.cornerRadius

            Flickable {
              id: detailFlick
              anchors.fill: parent
              anchors.margins: Style.space(18)
              clip: true
              contentWidth: width
              contentHeight: detailColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              visible: root.currentItem !== null

              ColumnLayout {
                id: detailColumn
                width: detailFlick.width
                spacing: Style.space(12)

                Text {
                  textFormat: Text.PlainText
                  text: root.currentItem ? String(root.currentItem.repo || "") : ""
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 0.6
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.currentItem ? String(root.currentItem.title || "Untitled") : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: root.currentItem ? root.stateLabel(root.currentItem) : ""
                    color: root.currentItem && root.currentItem.state ? root.stateColor(root.currentItem.state) : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.currentItem && root.currentItem.author ? "BY @" + String(root.currentItem.author).toUpperCase() : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Item { Layout.fillWidth: true }

                  Text {
                    textFormat: Text.PlainText
                    text: root.currentItem ? root.relativeTime(root.currentItem.updatedAt) : ""
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                PanelSeparator {
                  Layout.fillWidth: true
                  foreground: root.foreground
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.currentItem && root.currentItem.body ? String(root.currentItem.body) : "Open this item on GitHub for its full context."
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.Wrap
                  lineHeight: 1.35
                  Layout.fillWidth: true
                }

                Rectangle {
                  Layout.preferredWidth: openLabel.implicitWidth + Style.space(24)
                  Layout.preferredHeight: Style.space(36)
                  color: openMouse.pressed
                    ? Style.pressedFillFor(root.foreground, root.accent)
                    : (openMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.accent) : Style.selectedFillFor(root.foreground, root.accent))
                  radius: Style.cornerRadius
                  opacity: root.currentItem && root.currentItem.url ? 1 : 0.45
                  Accessible.role: Accessible.Button
                  Accessible.name: "Open selected item on GitHub"
                  Accessible.onPressAction: root.openCurrentItem()

                  Text {
                    id: openLabel
                    anchors.centerIn: parent
                    text: "OPEN ON GITHUB  ↗"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 0.6
                  }

                  MouseArea {
                    id: openMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.currentItem && root.currentItem.url
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.openCurrentItem()
                  }
                }

                Text {
                  text: "ENTER OR O TO OPEN"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 0.5
                }
              }
            }

            ColumnLayout {
              anchors.centerIn: parent
              width: Math.min(parent.width - Style.space(32), Style.space(300))
              spacing: Style.space(8)
              visible: root.currentItem === null

              Text {
                text: "SELECT AN ITEM"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.0
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }

              Text {
                text: "Its context and current state will appear here."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
              }
            }
          }
        }
      }
    }
  }
}
