import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.opencode-model-usage"

  property bool popupOpen: false
  property bool settingsMode: false
  property var draftSettings: ({})
  property string settingsStatusText: ""
  property bool refreshFlash: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color border: Color.popups.border
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.45)
  readonly property color card: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.055)
  readonly property color cardHover: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.085)
  readonly property color outline: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.18)
  readonly property color track: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.24)
  readonly property string fontFamily: bar ? bar.fontFamily : "JetBrainsMono Nerd Font"

  readonly property var provider: usageMain.enabledProviders.length > 0 ? usageMain.enabledProviders[0] : null

  function close() {
    popupOpen = false
    settingsMode = false
  }

  function triggerPress(button) {
    if (button === Qt.RightButton) {
      openSettings()
      return
    }
    if (button === Qt.MiddleButton) {
      triggerRefresh()
      return
    }

    if (popupOpen) {
      popupOpen = false
    } else {
      popupOpen = true
      triggerRefresh()
    }
  }

  function triggerRefresh() {
    refreshFlash = true
    refreshFlashTimer.restart()
    usageMain.refreshAll(true)
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function cloneObject(value, fallback) {
    if (value === undefined || value === null) return fallback
    try { return JSON.parse(JSON.stringify(value)) }
    catch (e) { return fallback }
  }

  function defaultSettings() {
    return { refreshIntervalSec: 300 }
  }

  function normalizedSettings(source) {
    var next = cloneObject(source, {}) || {}
    var refresh = Number(next.refreshIntervalSec === undefined || next.refreshIntervalSec === null ? 300 : next.refreshIntervalSec)
    next.refreshIntervalSec = Math.round(clamp(isFinite(refresh) ? refresh : 300, 30, 3600))
    return next
  }

  function openSettings() {
    draftSettings = normalizedSettings(settings)
    settingsStatusText = ""
    settingsMode = true
    popupOpen = true
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function showUsage() {
    settingsMode = false
    settingsStatusText = ""
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function canPersistSettings() {
    return !!(bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
  }

  function saveSettings() {
    var next = normalizedSettings(draftSettings)
    draftSettings = next
    root.settings = next
    if (canPersistSettings()) {
      bar.shell.updateEntryInline(root.moduleName, next)
      settingsStatusText = "Saved to shell.json"
    } else {
      settingsStatusText = "Saved for this session"
    }
    usageMain.refreshAll(true)
  }

  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  function iconSource() {
    return Qt.resolvedUrl("assets/opencode.svg")
  }

  function usagePercent() {
    return -1
  }

  function formatUsagePercent() {
    var toks = provider ? (provider.todayTotalTokens || 0) : 0
    if (toks <= 0) return ""
    return usageMain.formatTokenCount(toks)
  }

  function tooltipText() {
    if (!provider) return "OpenCode Usage"
    var line = provider.providerName + ": " + usageMain.formatTokenCount(provider.todayTotalTokens || 0) + " tokens today"
    return line
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onPopupOpenChanged: {
    if (popupOpen)
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usageMain
    settings: root.settings
  }

  Timer {
    id: refreshFlashTimer
    interval: 900
    repeat: false
    onTriggered: root.refreshFlash = false
  }

  IpcHandler {
    target: "omarchy.opencode-model-usage"
    function open(): string { root.showUsage(); root.popupOpen = true; return "ok" }
    function close(): string { root.close(); return "ok" }
    function toggle(): string {
      if (root.popupOpen) root.close()
      else { root.showUsage(); root.popupOpen = true }
      return "ok"
    }
    function refresh(): string { root.triggerRefresh(); return "ok" }
    function settings(): string { root.openSettings(); return "ok" }
    function openSettings(): string { root.openSettings(); return "ok" }
  }

  component UsageChip: Item {
    id: chip

    readonly property bool compact: root.vertical
    readonly property bool tooltipHovered: mouseArea.containsMouse

    width: compact ? root.barSize : chipRow.implicitWidth
    height: compact ? Math.max(root.barSize, chipColumn.implicitHeight + Style.space(2)) : root.barSize

    Row {
      id: chipRow
      visible: !chip.compact
      anchors.centerIn: parent
      spacing: 4

      Image {
        source: root.iconSource()
        width: 13
        height: 13
        sourceSize.width: 13
        sourceSize.height: 13
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: root.formatUsagePercent()
        color: foreground
        font.family: fontFamily
        font.pixelSize: 10
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
      }
    }

    Column {
      id: chipColumn
      visible: chip.compact
      anchors.centerIn: parent
      spacing: 1

      Image {
        source: root.iconSource()
        width: 13
        height: 13
        sourceSize.width: 13
        sourceSize.height: 13
        fillMode: Image.PreserveAspectFit
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Text {
        width: root.barSize
        text: root.formatUsagePercent()
        color: foreground
        font.family: fontFamily
        font.pixelSize: 10
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
      }
    }

    property var registeredBar: null

    function triggerPress(button) {
      root.triggerPress(button)
    }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(chip)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(chip)

    Connections {
      target: root
      function onBarChanged() { chip.syncClickRegistration() }
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(chip, root.tooltipText())
      onExited: if (root.bar) root.bar.hideTooltip(chip)
      onClicked: function(mouse) { root.triggerPress(mouse.button) }
    }
  }

  component EmptyUsageChip: Item {
    id: emptyChip
    readonly property bool tooltipHovered: emptyMouse.containsMouse
    visible: !provider
    width: root.vertical ? root.barSize : emptyLabel.implicitWidth
    height: root.barSize

    property var registeredBar: null

    function triggerPress(button) { root.triggerPress(button) }

    function syncClickRegistration() {
      if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(emptyChip)
      registeredBar = root.bar
      if (registeredBar && registeredBar.registerClickTarget) registeredBar.registerClickTarget(emptyChip)
    }

    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: if (registeredBar && registeredBar.unregisterClickTarget) registeredBar.unregisterClickTarget(emptyChip)

    Connections {
      target: root
      function onBarChanged() { emptyChip.syncClickRegistration() }
    }

    Text {
      id: emptyLabel
      anchors.centerIn: parent
      text: "OC"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      font.bold: true
    }

    MouseArea {
      id: emptyMouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(emptyChip, "OpenCode Usage")
      onExited: if (root.bar) root.bar.hideTooltip(emptyChip)
      onClicked: function(mouse) { root.triggerPress(mouse.button) }
    }
  }

  Item {
    id: button
    anchors.fill: parent
    implicitWidth: root.vertical ? root.barSize : barRow.implicitWidth + Style.space(10)
    implicitHeight: root.vertical ? barColumn.implicitHeight : root.barSize

    Row {
      id: barRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(8)
      UsageChip { visible: !root.vertical }
      EmptyUsageChip { visible: !root.vertical && (!provider || !provider.hasLocalStats) }
    }

    Column {
      id: barColumn
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)
      UsageChip { visible: root.vertical }
      EmptyUsageChip { visible: root.vertical && (!provider || !provider.hasLocalStats) }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(370))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: settingsMode && settingsContent.editorActive

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) flick.contentY = root.clamp(flick.contentY + dy * 56, 0, Math.max(0, flick.contentHeight - flick.height))
      }
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.triggerRefresh()
        if (t === "s" || t === "S") root.settingsMode ? root.saveSettings() : root.openSettings()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Header {
          visible: !root.settingsMode && !!root.provider
          provider: root.provider
        }

        SettingsHeader { visible: root.settingsMode }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        Flickable {
          id: flick
          Layout.fillWidth: true
          Layout.fillHeight: true
          contentWidth: width
          contentHeight: contentColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          ColumnLayout {
            id: contentColumn
            width: flick.width
            spacing: 10

            Text {
              visible: !root.settingsMode && (!root.provider || !root.provider.hasLocalStats)
              Layout.fillWidth: true
              Layout.topMargin: 24
              text: "No usage data yet. Start an OpenCode session to see stats."
              color: dim
              font.family: fontFamily
              font.pixelSize: 11
              horizontalAlignment: Text.AlignHCenter
            }

            StatusCard { provider: root.settingsMode ? null : root.provider }
            TodayCard { provider: root.settingsMode ? null : root.provider }
            WeekCard { provider: root.settingsMode ? null : root.provider }
            AllTimeCard { provider: root.settingsMode ? null : root.provider }

            UsageFooter { visible: !root.settingsMode }
            SettingsContent {
              id: settingsContent
              visible: root.settingsMode
            }
          }
        }
      }
    }
  }

  component SettingsHeader: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      text: "OpenCode Usage Settings"
      color: foreground
      font.family: fontFamily
      font.pixelSize: 15
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      text: "Usage"
      foreground: root.foreground
      tooltipText: "Back to usage"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      onClicked: root.showUsage()
    }

    Button {
      text: "Save"
      foreground: root.foreground
      tooltipText: "Save settings"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: true
      onClicked: root.saveSettings()
    }
  }

  component UsageFooter: RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Text {
      Layout.fillWidth: true
      text: "j/k scroll · r refresh · s/settings · esc close"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }
  }

  component SettingsContent: ColumnLayout {
    id: settingsRoot
    Layout.fillWidth: true
    spacing: 10

    readonly property bool editorActive: refreshIntervalField.field.activeFocus

    SectionCard {
      title: "Refresh"

      ColumnLayout {
        width: parent.width
        spacing: 8

        NumberField {
          id: refreshIntervalField
          label: "Refresh interval (seconds)"
          value: Number(root.draftValue("refreshIntervalSec", 300))
          from: 30
          to: 3600
          stepSize: 30
          fieldWidth: parent.width
          foreground: root.foreground
          accent: Color.accent
          fontFamily: root.fontFamily
          onModified: function(value) { root.setDraftValue("refreshIntervalSec", value) }
        }

        Text {
          Layout.fillWidth: true
          text: "How often the widget rescans the opencode database."
          color: dim
          font.family: fontFamily
          font.pixelSize: 10
          wrapMode: Text.WordWrap
        }
      }
    }

    Text {
      visible: root.settingsStatusText !== ""
      Layout.fillWidth: true
      text: root.settingsStatusText
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
    }

    Text {
      Layout.fillWidth: true
      text: "s saves · esc closes"
      color: dim
      font.family: fontFamily
      font.pixelSize: 10
      horizontalAlignment: Text.AlignHCenter
    }
  }

  function draftValue(name, fallback) {
    var value = draftSettings ? draftSettings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function setDraftValue(name, value) {
    var next = normalizedSettings(draftSettings)
    next[name] = value
    draftSettings = next
  }

  component Header: RowLayout {
    property var provider: null
    visible: !!provider
    Layout.fillWidth: true
    spacing: 8

    Image {
      source: root.iconSource()
      Layout.preferredWidth: 16
      Layout.preferredHeight: 16
      sourceSize.width: 16
      sourceSize.height: 16
      fillMode: Image.PreserveAspectFit
      Layout.alignment: Qt.AlignVCenter
    }

    Text {
      text: provider ? provider.providerName + " Usage" : ""
      color: foreground
      font.family: fontFamily
      font.pixelSize: 15
      font.bold: true
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }

    Button {
      text: (root.refreshFlash || usageMain.refreshing) ? "Refreshing\u2026" : "Refresh"
      foreground: root.foreground
      tooltipText: (root.refreshFlash || usageMain.refreshing) ? "Refreshing usage\u2026" : "Refresh usage"
      tooltipBackground: root.background
      tooltipForeground: root.foreground
      fontFamily: root.fontFamily
      fontSize: 10
      horizontalPadding: 8
      verticalPadding: 4
      active: root.refreshFlash || usageMain.refreshing
      onClicked: {
        root.triggerRefresh()
        keyCatcher.forceActiveFocus()
      }
    }
  }

  component StatusCard: SectionCard {
    property var provider: null
    visible: !!provider && String(provider.usageStatusText || "") !== ""
    titleColor: urgent
    title: provider ? provider.usageStatusText : ""
    subtitle: provider ? provider.authHelpText : ""
  }

  component TodayCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.ready && provider.hasLocalStats
    title: "Today"

    ColumnLayout {
      width: parent.width
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        spacing: 20
        StatBlock { value: provider ? String(provider.todaySessions || 0) : "0"; label: "sessions" }
        StatBlock { value: provider ? usageMain.formatTokenCount(provider.todayTotalTokens || 0) : "0"; label: "tokens" }
      }
      Repeater {
        model: {
          var toks = provider ? (provider.todayTokensByModel || {}) : {}
          var out = []
          for (var k in toks) out.push({ modelId: k, count: toks[k] })
          return out
        }
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          Text { text: usageMain.friendlyModelName(modelData.modelId); color: dim; font.family: fontFamily; font.pixelSize: 11 }
          Item { Layout.fillWidth: true }
          Text { text: usageMain.formatTokenCount(modelData.count) + " tokens"; color: foreground; font.family: fontFamily; font.pixelSize: 11; font.bold: true }
        }
      }
    }
  }

  component WeekCard: SectionCard {
    property var provider: null
    visible: !!provider && provider.recentDays && provider.recentDays.length > 0
               && provider.recentDays.some(function(d) { return d.messageCount > 0 })
    title: "Last 7 Days"

    ColumnLayout {
      width: parent.width
      spacing: 6
      Repeater {
        model: provider ? provider.recentDays : []
        delegate: RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 8
          readonly property real count: modelData ? Number(modelData.messageCount || 0) : 0
          readonly property real maxCount: {
            var days = provider ? (provider.recentDays || []) : []
            var max = 1
            for (var i = 0; i < days.length; i++) if (Number(days[i].messageCount || 0) > max) max = Number(days[i].messageCount || 0)
            return max
          }
          Text {
            text: {
              var d = modelData.date
              if (!d) return ""
              var dt = new Date(d + "T00:00:00")
              var names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
              return names[dt.getDay()] + " " + String(dt.getMonth() + 1).padStart(2, "0") + "/" + String(dt.getDate()).padStart(2, "0")
            }
            color: dim
            font.family: fontFamily
            font.pixelSize: 10
            Layout.preferredWidth: 48
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
            color: track
            radius: Math.max(1, Style.cornerRadius / 3)
            Rectangle {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: parent.width * (count / maxCount)
              color: root.alpha(foreground, 0.78)
              radius: Math.max(1, Style.cornerRadius / 3)
              Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
          }
          Text {
            text: usageMain.formatTokenCount(count)
            color: foreground
            font.family: fontFamily
            font.pixelSize: 10
            font.bold: true
            horizontalAlignment: Text.AlignRight
            Layout.preferredWidth: 48
          }
        }
      }
    }
  }

  component AllTimeCard: SectionCard {
    property var provider: null
    visible: {
      var usage = provider ? (provider.modelUsage || {}) : {}
      return Object.keys(usage).length > 0
    }
    title: "All-Time"

    ColumnLayout {
      width: parent.width
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        spacing: 20
        StatBlock { value: provider ? String(provider.totalSessions || 0) : "0"; label: "sessions" }
      }
      PanelSeparator { Layout.fillWidth: true; foreground: root.foreground; strength: 0.18 }
      Repeater {
        model: {
          var usage = provider ? (provider.modelUsage || {}) : {}
          var out = []
          for (var k in usage) out.push({ modelId: k, data: usage[k] })
          return out
        }
        delegate: ColumnLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: 4
          Text { text: usageMain.friendlyModelName(modelData.modelId); color: foreground; font.family: fontFamily; font.pixelSize: 11; font.bold: true }
          GridLayout {
            Layout.leftMargin: 10
            columns: 2
            columnSpacing: 18
            rowSpacing: 2
            DetailPair { name: "Input"; value: usageMain.formatTokenCount(modelData.data.inputTokens || 0) }
            DetailPair { name: "Output"; value: usageMain.formatTokenCount(modelData.data.outputTokens || 0) }
            DetailPair { name: "Cache Read"; value: usageMain.formatTokenCount(modelData.data.cacheReadInputTokens || 0) }
            DetailPair { name: "Cache Write"; value: usageMain.formatTokenCount(modelData.data.cacheCreationInputTokens || 0) }
          }
        }
      }
    }
  }

  component SectionCard: BorderSurface {
    id: section
    property string title: ""
    property string subtitle: ""
    property color titleColor: foreground
    default property alias content: body.data

    Layout.fillWidth: true
    color: card
    borderSpec: Border.flat(Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05), 1)
    padding: 12
    radius: Style.cornerRadius
    implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: section.contentTopInset
      anchors.rightMargin: section.contentRightInset
      anchors.bottomMargin: section.contentBottomInset
      anchors.leftMargin: section.contentLeftInset
      spacing: 8

      PanelSectionHeader {
        visible: section.title !== ""
        Layout.fillWidth: true
        text: section.title
        foreground: section.titleColor
        fontFamily: root.fontFamily
        fontSize: 11
      }
      Text {
        visible: section.subtitle !== ""
        Layout.fillWidth: true
        text: section.subtitle
        color: dim
        font.family: fontFamily
        font.pixelSize: 10
        wrapMode: Text.WordWrap
      }
    }
  }

  component StatBlock: ColumnLayout {
    property string value: "0"
    property string label: ""
    spacing: 2
    Text { text: value; color: foreground; font.family: fontFamily; font.pixelSize: 18; font.bold: true }
    Text { text: label; color: dim; font.family: fontFamily; font.pixelSize: 10 }
  }

  component DetailPair: RowLayout {
    property string name: ""
    property string value: ""
    Text { text: name; color: dim; font.family: fontFamily; font.pixelSize: 10; Layout.preferredWidth: 76 }
    Text { text: value; color: foreground; font.family: fontFamily; font.pixelSize: 10; font.bold: true }
  }
}
