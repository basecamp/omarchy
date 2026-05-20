import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "weather"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: bar && bar.vertical ? button.implicitWidth : button.implicitWidth + Style.spacing.controlGap
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("../../panels/weather.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.verticalCenter: parent.verticalCenter
    x: bar && bar.vertical ? Math.round((parent.width - width) / 2) : 0
    width: implicitWidth
    height: implicitHeight
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.label : ""
    active: panelLoader.item && panelLoader.item.klass === "active"
    horizontalMargin: 1
    // Tooltip suppressed because the panel is the detail view.
    tooltipText: ""

    onPressed: function(b) {
      if (!root.bar) return
      if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
