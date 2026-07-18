import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.system-update"

  property bool popupOpen: false
  property string activeTab: "packages"
  readonly property bool opened: popupOpen

  readonly property var updateService: bar && bar.shell
    ? bar.shell.firstPartyServiceFor("omarchy.system-update")
    : null
  readonly property int updateCount: updateService ? updateService.totalUpdateCount : 0
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property bool hasMaterialSymbols: Qt.fontFamilies().indexOf("Material Symbols Rounded") !== -1

  function open() {
    popupOpen = true
  }

  function close() {
    popupOpen = false
  }

  function tooltipText() {
    if (!updateService) return "Update center is loading"
    if (updateService.packageRefreshing || updateService.themeRefreshing) return "Checking for updates"
    var parts = []
    if (updateService.packageCount > 0) parts.push(updateService.packageCount + " package" + (updateService.packageCount === 1 ? "" : "s"))
    if (updateService.themeCount > 0) parts.push(updateService.themeCount + " theme" + (updateService.themeCount === 1 ? "" : "s"))
    if (updateService.packageError !== "" || updateService.packageState.state === "unavailable" || updateService.packageState.state === "invalid")
      parts.push("package check unavailable")
    if (updateService.themeError !== "" || updateService.themeState.degraded === true)
      parts.push("theme check incomplete")
    else if (Number(updateService.themeState.review || 0) > 0)
      parts.push(updateService.themeState.review + " theme review")
    if (parts.length === 0 && (updateService.packageState.state === "loading"
        || Number(updateService.themeState.checkedEpoch || 0) <= 0))
      return "Update status has not been checked"
    if (parts.length === 0) return "System and user themes are up to date"
    return parts.join(" · ")
  }

  onPopupOpenChanged: {
    if (popupOpen && updateService) activeTab = updateService.preferredTab()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Style.bar.statusSlot
    fixedHeight: root.vertical ? Style.bar.statusSlot : -1
    active: root.updateCount > 0 || (root.updateService && root.updateService.needsAttention)
    activeColor: root.bar ? root.bar.urgent : Color.bar.active
    tooltipText: root.tooltipText()

    onPressed: function(mouseButton) {
      if (!root.updateService) return
      if (mouseButton === Qt.RightButton) root.updateService.refreshAll()
      else root.popupOpen = !root.popupOpen
    }

    Item {
      anchors.centerIn: parent
      width: Style.space(20)
      height: Style.space(20)

      Text {
        id: updateIcon
        anchors.centerIn: parent
        // Match QS Rise V1's package_2 icon without making its optional icon
        // font a hard dependency of the stock Omarchy shell.
        text: root.hasMaterialSymbols ? "\uF569" : "\uf466"
        color: button.active ? button.activeColor : button.foreground
        font.family: root.hasMaterialSymbols ? "Material Symbols Rounded" : root.bar.fontFamily
        font.pixelSize: root.hasMaterialSymbols ? Style.bar.iconFont + 1 : Style.bar.iconFont
        font.variableAxes: root.hasMaterialSymbols ? { "FILL": 0 } : ({})
        renderType: root.hasMaterialSymbols ? Text.QtRendering : Text.NativeRendering
      }

      Rectangle {
        visible: root.updateCount > 0
        anchors.verticalCenter: updateIcon.verticalCenter
        anchors.verticalCenterOffset: -Style.space(6)
        anchors.horizontalCenter: updateIcon.horizontalCenter
        anchors.horizontalCenterOffset: Style.space(7)
        width: Math.max(Style.space(12), badgeText.implicitWidth + Style.space(6))
        height: Style.space(12)
        radius: height / 2
        color: root.bar ? root.bar.urgent : Color.bar.active

        Text {
          id: badgeText
          anchors.centerIn: parent
          text: root.updateCount > 99 ? "99+" : String(root.updateCount)
          color: Color.background
          font.family: root.bar.fontFamily
          font.pixelSize: Math.max(Style.space(7), Style.font.caption - 3)
          font.bold: true
        }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.popupOpen
    centerOnBar: true
    contentWidth: popup.fittedContentWidth(Style.space(570))
    contentHeight: popup.cappedContentHeight(Style.space(530))

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(10)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)

          Text {
            Layout.fillWidth: true
            text: "Updates"
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            Layout.fillWidth: true
            text: root.updateService
              ? root.updateService.totalUpdateCount + " pending across official packages and user themes"
              : "Loading update service"
            color: root.dim
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Button {
          iconText: "\uf021"
          tooltipText: "Check packages and user themes"
          enabled: root.updateService && !root.updateService.busy
          foreground: root.foreground
          fontFamily: root.bar.fontFamily
          bordered: true
          onClicked: root.updateService.refreshAll()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Repeater {
          model: [
            { key: "packages", label: "Packages", count: root.updateService ? root.updateService.packageCount : 0 },
            { key: "themes", label: "Themes", count: root.updateService ? root.updateService.themeCount : 0 }
          ]

          delegate: Button {
            required property var modelData
            Layout.fillWidth: true
            text: modelData.label + (modelData.count > 0 ? "  " + modelData.count : "")
            selected: root.activeTab === modelData.key
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.body
            bordered: true
            onClicked: root.activeTab = modelData.key
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Loader {
          anchors.fill: parent
          active: root.updateService !== null && root.activeTab === "packages"
          sourceComponent: packagesComponent
        }

        Loader {
          anchors.fill: parent
          active: root.updateService !== null && root.activeTab === "themes"
          sourceComponent: themesComponent
        }

        Text {
          anchors.centerIn: parent
          visible: root.updateService === null
          text: "Loading update service…"
          color: root.dim
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Component {
          id: packagesComponent
          PackagesTab {
            updateService: root.updateService
            bar: root.bar
          }
        }

        Component {
          id: themesComponent
          ThemesTab {
            updateService: root.updateService
            bar: root.bar
          }
        }
      }
    }
  }
}
