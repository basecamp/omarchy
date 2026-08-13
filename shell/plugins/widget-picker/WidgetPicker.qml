import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "WidgetPickerModel.js" as PickerModel

// The add-widget picker: a searchable list of every installed bar widget not
// already on the bar. Summoned bare it appends at the widget's default spot;
// summoned from a right-click on the bar it lands the pick on the insertion
// edge that was under the pointer, carried in the summon payload.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  // { section?, before?/after? } in putBarWidget terms, from the summon payload.
  property var placement: ({})
  property string screenName: ""
  property var rows: []
  property var filteredRows: []

  // Shares the [menu] surface tokens — themes that style the menu also style
  // the picker.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Style.font.title + Style.font.body + Style.spacing.md * 2 + Style.spacing.xs
  property int cardWidth: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(460), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    var parsed = PickerModel.parsePlacement(payloadJson)
    root.placement = parsed.placement
    root.screenName = parsed.screen
    root.filterText = ""
    root.selectedIndex = 0
    root.opened = true
    root.rebuild()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.widget-picker")
  }

  function rebuild() {
    var installed = root.pluginRegistry ? root.pluginRegistry.installedPlugins : {}
    var onBar = []
    for (var id in installed) {
      if (root.pluginRegistry.inBar(id)) onBar.push(id)
    }
    root.rows = PickerModel.pickerRows(installed, onBar)
    root.refilter()
  }

  function refilter() {
    root.filteredRows = PickerModel.filterRows(root.rows, root.filterText)
    if (root.selectedIndex >= root.filteredRows.length) root.selectedIndex = Math.max(0, root.filteredRows.length - 1)
    Qt.callLater(function() {
      if (root.filteredRows.length > 0) resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function setFilter(nextFilter) {
    root.filterText = nextFilter
    root.selectedIndex = 0
    root.refilter()
  }

  function select(delta) {
    if (root.filteredRows.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.filteredRows.length) % root.filteredRows.length
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activateIndex(index) {
    var row = root.filteredRows[index]
    if (!row || !root.pluginRegistry) return

    var error = root.pluginRegistry.putBarWidget(row.id, root.placement)
    root.dismiss()
    if (error)
      Quickshell.execDetached(["omarchy-notification-send", "Menu Bar", "Could not add " + row.name + ": " + error])
  }

  function screenByName(name) {
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (String(Quickshell.screens[i].name || "") === name) return Quickshell.screens[i]
    }
    return null
  }

  // A widget added or removed while the picker is open (another session, the
  // CLI) changes what there is to offer.
  Connections {
    target: root.pluginRegistry
    function onPluginsChanged() {
      if (root.opened) root.rebuild()
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    // Opens on the bar the summon named, or the default screen.
    screen: root.screenByName(root.screenName) || Quickshell.screens[0]
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-widget-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card

      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Add a widget…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: parent.height - root.headerHeight - root.contentSpacing

          ListView {
            id: resultList

            anchors.fill: parent
            model: root.filteredRows
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: rowDelegate

              required property int index
              required property var modelData

              readonly property bool hasCursor: index === root.selectedIndex
              readonly property color rowColor: hasCursor ? root.selectedText : root.foreground

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              Column {
                anchors.left: parent.left
                anchors.right: categoryLabel.left
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  text: rowDelegate.modelData.name
                  color: rowDelegate.rowColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: rowDelegate.modelData.description
                  visible: text !== ""
                  color: rowDelegate.rowColor
                  opacity: 0.62
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }

              Text {
                id: categoryLabel

                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: rowDelegate.modelData.category
                color: rowDelegate.rowColor
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = rowDelegate.index
                onClicked: root.activateIndex(rowDelegate.index)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(8)
            visible: root.filteredRows.length === 0

            Text {
              width: parent.width
              text: root.filterText ? "No matches for “" + root.filterText + "”" : "Every installed widget is already on the bar"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
            }
          }
        }
      }
    }
  }
}
