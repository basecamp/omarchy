import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

// Searchable single-select dropdown. Same trigger shape as Dropdown, but
// the popup leads with an embedded TextField that filters the option
// list in real time. Use for pickers with enough options that scanning
// is friction (e.g. bar settings "+ Add widget").
//
// Filtering is case-insensitive substring against each option's label.
// Options can be string[] or [{ value, label, description? }] — the same
// shape Dropdown accepts. The filter clears whenever the popup closes.
//
// Keyboard: Tab to focus the trigger, Enter/Space opens (search focused
// immediately). Down arrow from the search jumps to the first match;
// Up from the first match returns to the search. Enter selects, Esc
// closes (and clears the filter).
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property string placeholderText: "Search..."
  property string emptyText: "No matches"

  property color foreground: Color.foreground
  property color background: Color.popups.background
  property color popupBorder: Color.popups.border
  property color accent: Color.accent
  property string fontFamily: "JetBrainsMono Nerd Font"
  property int rowHeight: 28
  property int popupRowHeight: 28
  property int popupMinHeight: 220
  property bool showLabel: true

  // Panel-cursor flag. When true, the trigger renders the same focus ring
  // as Tab-focus so a panel's keyboard cursor lands here identically.
  // Emits `hovered(bool)` on pointer enter/leave so the panel can keep
  // its cursor state in sync with the mouse.
  property bool hasCursor: false

  // popupOpen + open()/close()/toggle() let a parent panel know when the
  // dropdown owns keys (search field + result list are active) and
  // suspend its own keyCatcher so typing into the filter doesn't drive
  // the panel cursor.
  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function optionDescription(o) {
    return (o && typeof o === "object" && o.description) ? String(o.description) : ""
  }
  function currentLabel() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }

  property var filtered: options
  function recomputeFiltered() {
    var q = searchField.text.toLowerCase()
    if (!q) { filtered = options; return }
    var out = []
    for (var i = 0; i < options.length; i++) {
      var lbl = optionLabel(options[i]).toLowerCase()
      var desc = optionDescription(options[i]).toLowerCase()
      if (lbl.indexOf(q) !== -1 || desc.indexOf(q) !== -1) out.push(options[i])
    }
    filtered = out
  }

  onOptionsChanged: recomputeFiltered()

  implicitWidth: 260
  implicitHeight: showLabel && label !== "" ? rowHeight + 18 : rowHeight

  Column {
    anchors.fill: parent
    spacing: 4

    Text {
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true
    }

    Rectangle {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus || root.hasCursor

      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b,
                     trigger._focused ? 0.08 : 0.04)
      border.color: trigger._focused
        ? Style.focusBorderColor
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.4)
      border.width: trigger._focused ? Style.focusBorderWidth : 1

      activeFocusOnTab: true

      HoverHandler {
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 6
        text: root.currentLabel() || root.placeholderText
        color: root.currentLabel() ? root.foreground : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: 12
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: 8
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: 12
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      QQC.Popup {
        id: popup
        x: 0
        y: trigger.height + 2
        width: trigger.width
        implicitHeight: Math.max(root.popupMinHeight,
                                 Math.min(resultList.contentHeight + 50,
                                          root.popupRowHeight * 6 + 5 * 4 + 50))
        padding: 1
        focus: true

        background: Rectangle {
          color: root.background
          border.color: root.popupBorder
          border.width: 1
          radius: Style.cornerRadius
        }

        onOpened: {
          searchField.text = ""
          root.recomputeFiltered()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onClosed: searchField.text = ""

        contentItem: Column {
          spacing: 0

          Item {
            width: parent.width
            height: 38

            TextField {
              id: searchField
              anchors.fill: parent
              anchors.margins: 6
              placeholderText: root.placeholderText
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: 12

              onTextChanged: {
                root.recomputeFiltered()
                if (resultList.count > 0) resultList.currentIndex = 0
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                  if (resultList.count > 0) {
                    resultList.currentIndex = 0
                    resultList.forceActiveFocus()
                  }
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  if (resultList.count > 0) {
                    resultList.currentIndex = 0
                    resultList.selectCurrent()
                  }
                  event.accepted = true
                }
              }
            }
          }

          Rectangle {
            width: parent.width
            height: 1
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
          }

          Item {
            width: parent.width
            height: popup.height - 38 - 2 - 1

            Text {
              anchors.centerIn: parent
              visible: resultList.count === 0
              text: root.emptyText
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: 12
            }

            ListView {
              id: resultList
              anchors.fill: parent
              spacing: 4
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.filtered
              currentIndex: -1
              keyNavigationEnabled: false

              function selectCurrent() {
                if (currentIndex < 0 || currentIndex >= root.filtered.length) return
                var v = root.optionValue(root.filtered[currentIndex])
                root.value = v
                root.changed(v)
                popup.close()
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === Qt.Key_Down || event.text === "j") {
                  if (resultList.currentIndex >= resultList.count - 1) {
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex + 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Up || event.text === "k") {
                  if (resultList.currentIndex <= 0) {
                    searchField.forceActiveFocus()
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex - 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  resultList.selectCurrent(); event.accepted = true
                }
              }

              delegate: Rectangle {
                required property var modelData
                required property int index
                width: resultList.width
                height: Math.max(root.popupRowHeight, rowContent.implicitHeight + 12)
                color: index === resultList.currentIndex
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
                  : "transparent"

                Column {
                  id: rowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  spacing: 2

                  Text {
                    text: root.optionLabel(modelData)
                    color: index === resultList.currentIndex ? root.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                  }
                  Text {
                    visible: text !== ""
                    text: root.optionDescription(modelData)
                    color: Qt.darker(root.foreground, 1.5)
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: resultList.currentIndex = parent.index
                  onClicked: resultList.selectCurrent()
                }
              }
            }
          }
        }
      }
    }
  }
}
