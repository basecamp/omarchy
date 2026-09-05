import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.weather"

  // "showTemperature" on the bar entry turns the icon-only pill into a padded
  // "<icon> <temp>°" label, laid out like the clock. Default is icon-only, so
  // an existing bar is unchanged. Vertical bars keep the compact icon-only
  // slot regardless (as the clock and media widgets do) -- a text label would
  // paint past the narrow edge.
  readonly property bool showTemperature: !vertical && setting("showTemperature", false) === true

  readonly property string barLabel: {
    var p = panelLoader.item
    if (!p) return ""
    if (!root.showTemperature || !p.reportTempNum) return p.label
    return p.label + " " + p.reportTempNum + p.tempUnit
  }

  // With the padded text label showing, the open-panel marker should span the
  // painted "<icon> <temp>°" text rather than 55% of the whole padded slot
  // (Bar.qml's fallback), the same hint the clock exposes. Icon-only keeps the
  // fallback, unchanged from the stock widget.
  readonly property real openPanelIndicatorWidth: root.showTemperature && button.item
    ? (button.item.labelWidth || 0)
    : 0

  function handlePress(b) {
    if (!root.bar) return
    if (b === Qt.RightButton) root.bar.run("omarchy-notification-send \"$(omarchy-weather-status)\"")
    else if (b === Qt.MiddleButton) root.refresh()
    else root.togglePanel()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (Bar.findPanelWidget
  // requires open/close/opened on the bar-widget root). Open maps to the
  // panel's hotkey path so summoning suppresses the center hover reveal,
  // matching what the old per-plugin IpcHandler did.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  visible: panelLoader.item && panelLoader.item.label !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  // Icon-only is a fixed square glyph slot (BarIconButton); the temperature
  // variant needs a padded text label (WidgetButton), the same split the bar
  // makes between icon widgets and text widgets like the clock.
  Loader {
    id: button
    anchors.fill: parent
    sourceComponent: root.showTemperature ? temperatureLabel : iconOnly
  }

  Component {
    id: iconOnly
    BarIconButton {
      bar: root.bar
      text: root.barLabel
      slotSize: Style.bar.statusSlot
      // Tooltip suppressed because the panel is the detail view.
      tooltipText: ""
      onPressed: function(b) { root.handlePress(b) }
    }
  }

  Component {
    id: temperatureLabel
    WidgetButton {
      bar: root.bar
      text: root.barLabel
      hasVisualContent: text !== ""
      horizontalMargin: 8.75
      verticalPadding: 8.75
      tooltipText: ""
      onPressed: function(b) { root.handlePress(b) }
    }
  }
}
