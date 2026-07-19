import QtQuick
import qs.Commons
import qs.Ui

// Deliberately invisible on the bar. This still has to be a "bar-widget"
// plugin instance (kept in bar.layout) because that's what keeps Panel.qml
// loaded and its `omarchy.calendar` IPC target registered — Clock.qml's
// click handler is the only way to open the calendar, so this component's
// only job is to host that Loader without taking up any bar space.
BarWidget {
  id: root
  moduleName: "omarchy.calendar"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = root
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root) — mirrors Weather,
  // even though nothing on the bar itself triggers these anymore.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  implicitWidth: 0
  implicitHeight: 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
