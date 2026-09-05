import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  function labCommand(name) {
    if (name.startsWith("/")) return name
    return Quickshell.env("OMARCHY_PATH") + "/bin/" + name
  }

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool busy: false
  property string openingTerminalAction: ""
  readonly property bool installerOpening: busy && actionLabel === "Opening installer"
  readonly property bool inlineInstallError: currentPage === 0 && !status.installed && actionLabel === "Opening installer" && errorText !== ""
  property bool resetArmed: armedAction === "reset"
  property string armedAction: ""
  property string errorText: ""
  property string actionOutput: ""
  property string stderrText: ""
  property string actionLabel: ""
  property bool closeAfterAction: false
  property int currentPage: 0
  property var status: Model.defaultStatus()
  property string healthSummary: "Health unavailable"
  property string networkSummary: "Network unavailable"
  property string resourceSummary: "Resources unavailable"
  property var resources: Model.defaultResources()
  property int customResourceCpus: 1
  property int customResourceMemoryGiB: 1
  property bool customResourcesDirty: false
  property string deploymentSummary: "No checkout deployed"
  property string goldSummary: "Gold image unavailable"
  property string artifactSummary: "No captured artifacts"
  property var branches: []
  property var checkpoints: []
  property var scenarios: []
  property string selectedBranch: ""
  property string selectedCheckpoint: ""
  property string selectedScenario: "smoke"
  property real cardOffsetX: 0
  property real cardOffsetY: 0

  readonly property string viewerCommand: labCommand("omarchy-lab-viewer")
  readonly property var pageOptions: ["Console", "Develop", "Environment", "Capture", "Automate"]
  readonly property var aspectOptions: ["16:9", "16:10", "3:2", "4:3", "21:9", "32:9"]
  readonly property var zoomOptions: ["50", "75", "100", "125", "150", "200"]
  readonly property var lightResources: Model.profileAllocation(resources, "light")
  readonly property var balancedResources: Model.profileAllocation(resources, "balanced")
  readonly property var performanceResources: Model.profileAllocation(resources, "performance")
  readonly property var fullResources: Model.profileAllocation(resources, "full")
  readonly property int maximumResourceCpus: Math.max(1, Number(resources.host.safeCpus || 1))
  readonly property int maximumResourceMemoryGiB: Model.memoryGiB(resources.host.safeMemoryBytes)
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string pluginId: (manifest && manifest.id) || "omarchy.lab"
  readonly property real currentPageHeight: {
    const pageHeights = [consolePage.implicitHeight, developPage.implicitHeight, environmentPage.implicitHeight, capturePage.implicitHeight, automatePage.implicitHeight]
    return pageHeights[currentPage] || 0
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(String(payloadJson || "{}")) || {} } catch (e) { payload = {} }
    opened = true
    armedAction = ""
    if (pageOptions.indexOf(String(payload.page || "")) !== -1)
      currentPage = pageOptions.indexOf(String(payload.page))
    refreshAll()
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    armedAction = ""
    errorText = ""
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function startProcess(process) {
    if (!process.running) process.running = true
  }

  function refreshAll() {
    startProcess(viewerStatusProc)
    startProcess(healthProc)
    startProcess(branchListProc)
    startProcess(checkoutStatusProc)
    startProcess(checkpointListProc)
    startProcess(networkStatusProc)
    startProcess(resourceStatusProc)
    startProcess(goldStatusProc)
    startProcess(artifactListProc)
    startProcess(scenarioListProc)
  }

  function runCommand(command, args, label, closeAfter) {
    if (busy || actionProc.running) return
    busy = true
    armedAction = ""
    confirmTimer.stop()
    errorText = ""
    actionOutput = ""
    stderrText = ""
    var terminalArgs = Model.terminalCommand(command, args)
    openingTerminalAction = terminalArgs ? terminalArgs[1] : ""
    actionLabel = terminalArgs ? "Opening " + label + " terminal" : label
    closeAfterAction = closeAfter === true || terminalArgs !== null
    actionProc.command = terminalArgs ? [labCommand("omarchy-lab-terminal-launch")].concat(terminalArgs) : [labCommand(command)].concat(args)
    actionProc.running = true
  }

  function runViewer(args, label, closeAfter) {
    runCommand(viewerCommand, args, label, closeAfter)
  }

  function openInstaller() {
    runCommand("omarchy-lab-install-launch", [], "Opening installer", true)
  }

  function openLab() {
    if (!status.installed) return
    runViewer(["launch"], "Opening Lab", true)
  }

  function terminalButtonText(action, text) {
    return busy && openingTerminalAction === action ? "Opening terminal…" : text
  }

  function actionFailedToStart() {
    if (!actionProc.running && busy) {
      busy = false
      errorText = "Could not start the Lab command. Check that the plugin is installed correctly and try again."
      closeAfterAction = false
    }
  }

  function recordViewer() {
    if (busy || actionProc.running) return
    close()
    runCommand("omarchy-lab-capture", ["record", "10", "--copy"], "Recording")
  }

  function setResourceProfile(profile, label) {
    customResourcesDirty = false
    runCommand("omarchy-lab-resource", ["set", profile], label + " resources")
  }

  function applyCustomResources() {
    customResourcesDirty = false
    runCommand("omarchy-lab-resource", ["set", "custom", String(customResourceCpus), String(customResourceMemoryGiB)], "Custom resources")
  }

  function armOrRun(key, command, args, label) {
    if (armedAction !== key) {
      armedAction = key
      confirmTimer.restart()
      actionOutput = "Select Confirm " + label + " within five seconds."
    } else {
      runCommand(command, args, label)
    }
  }

  function pageChanged(value) {
    currentPage = pageOptions.indexOf(value)
    pageScroll.contentItem.contentY = 0
    armedAction = ""
  }

  function moveCardTo(x, y) {
    var margin = Style.space(12)
    var horizontalLimit = Math.max(0, (keyCatcher.width - card.width) / 2 - margin)
    var verticalLimit = Math.max(0, (keyCatcher.height - card.height) / 2 - margin)
    cardOffsetX = Math.max(-horizontalLimit, Math.min(horizontalLimit, x))
    cardOffsetY = Math.max(-verticalLimit, Math.min(verticalLimit, y))
  }

  function moveCardBy(x, y) {
    moveCardTo(cardOffsetX + x, cardOffsetY + y)
  }

  function centerCard() {
    cardOffsetX = 0
    cardOffsetY = 0
  }

  function constrainCard() {
    if (!opened || keyCatcher.width <= 0 || keyCatcher.height <= 0) return
    moveCardTo(cardOffsetX, cardOffsetY)
  }

  Process {
    id: viewerStatusProc
    command: [root.viewerCommand, "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.status = Model.parseStatus(text) }
  }

  Process {
    id: healthProc
    command: [root.labCommand("omarchy-lab-health"), "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.healthSummary = Model.healthText(text) }
  }

  Process {
    id: branchListProc
    command: [root.labCommand("omarchy-lab-checkout"), "branches", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.branches = Model.branchOptions(text)
        var selectionFound = false
        for (var i = 0; i < root.branches.length; i++) {
          if (root.branches[i].value === root.selectedBranch) selectionFound = true
        }
        if (root.branches.length === 0) root.selectedBranch = ""
        else if (!selectionFound) root.selectedBranch = root.branches[0].value
      }
    }
  }

  Process {
    id: checkoutStatusProc
    command: [root.labCommand("omarchy-lab-checkout"), "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.deploymentSummary = Model.deploymentText(text) }
  }

  Process {
    id: checkpointListProc
    command: [root.labCommand("omarchy-lab-checkpoint"), "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.checkpoints = Model.checkpointOptions(text)
        if (root.checkpoints.length === 0) root.selectedCheckpoint = ""
        else if (root.selectedCheckpoint === "") root.selectedCheckpoint = root.checkpoints[0].value
      }
    }
  }

  Process {
    id: networkStatusProc
    command: [root.labCommand("omarchy-lab-network"), "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.networkSummary = Model.networkText(text) }
  }

  Process {
    id: resourceStatusProc
    command: [root.labCommand("omarchy-lab-resource"), "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseResources(text)
        root.resources = parsed
        root.resourceSummary = Model.resourceText(parsed)
        if (parsed.available && !root.customResourcesDirty) {
          root.customResourceCpus = parsed.cpus.configured
          root.customResourceMemoryGiB = Model.memoryGiB(parsed.memory.configuredBytes)
        }
      }
    }
  }

  Process {
    id: goldStatusProc
    command: [root.labCommand("omarchy-lab-gold"), "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.goldSummary = Model.goldText(text) }
  }

  Process {
    id: artifactListProc
    command: [root.labCommand("omarchy-lab-capture"), "list", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.artifactSummary = Model.artifactText(text) }
  }

  Process {
    id: scenarioListProc
    command: [root.labCommand("omarchy-lab-scenario"), "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.scenarios = Model.scenarioOptions(text)
        if (root.scenarios.length > 0 && root.selectedScenario === "") root.selectedScenario = root.scenarios[0].value
      }
    }
  }

  Process {
    id: actionProc
    onRunningChanged: {
      if (!running) Qt.callLater(root.actionFailedToStart)
    }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.actionOutput = String(text || "").trim() }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.stderrText = String(text || "").trim() }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.errorText = root.stderrText || root.actionLabel + " failed"
      else if (root.closeAfterAction) root.dismiss()
      root.closeAfterAction = false
      refreshDelay.restart()
    }
  }

  Timer { id: refreshTimer; interval: 5000; repeat: true; running: root.opened && !root.busy; onTriggered: root.refreshAll() }
  Timer { id: refreshDelay; interval: 600; onTriggered: root.refreshAll() }
  Timer { id: confirmTimer; interval: 5000; onTriggered: root.armedAction = "" }

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-lab-controls"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: root.dismiss() }
    Shortcut { sequence: "Ctrl+Left"; enabled: root.opened; onActivated: root.pageChanged(root.pageOptions[Math.max(0, root.currentPage - 1)]) }
    Shortcut { sequence: "Ctrl+Right"; enabled: root.opened; onActivated: root.pageChanged(root.pageOptions[Math.min(root.pageOptions.length - 1, root.currentPage + 1)]) }
    Shortcut { sequence: "Ctrl+R"; enabled: root.opened; onActivated: root.refreshAll() }
    Shortcut { sequence: "Alt+Left"; enabled: root.opened; onActivated: root.moveCardBy(-Style.space(40), 0) }
    Shortcut { sequence: "Alt+Right"; enabled: root.opened; onActivated: root.moveCardBy(Style.space(40), 0) }
    Shortcut { sequence: "Alt+Up"; enabled: root.opened; onActivated: root.moveCardBy(0, -Style.space(40)) }
    Shortcut { sequence: "Alt+Down"; enabled: root.opened; onActivated: root.moveCardBy(0, Style.space(40)) }
    Shortcut { sequence: "Alt+Home"; enabled: root.opened; onActivated: root.centerCard() }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: true
      onWidthChanged: Qt.callLater(function() { root.constrainCard() })
      onHeightChanged: Qt.callLater(function() { root.constrainCard() })

      BorderSurface {
        id: card
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root.cardOffsetX
        anchors.verticalCenterOffset: root.cardOffsetY
        width: Math.min(parent.width - Style.space(24), Style.space(960))
        height: Math.min(parent.height - Style.space(24), cardContent.implicitHeight + Style.space(40))
        color: Color.popups.background
        radius: Style.cornerRadius
        borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.normalBorderWidth))
        MouseArea { anchors.fill: parent; onClicked: {} }

        Behavior on height {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
        onHeightChanged: Qt.callLater(function() { root.constrainCard() })

        ColumnLayout {
          id: cardContent
          anchors.fill: parent
          anchors.margins: Style.space(20)
          spacing: Style.space(12)

          RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: Style.space(12)
            DragHandler {
              target: null
              acceptedButtons: Qt.LeftButton
              onTranslationChanged: function(delta) { root.moveCardBy(delta.x, delta.y) }
            }
            Text { text: "󰆧"; color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.display }
            ColumnLayout {
              spacing: Style.space(2)
              Text { text: "Omarchy Lab"; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.title; font.bold: true }
              Text { text: Model.statusText(root.status); textFormat: Text.PlainText; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall }
            }
            Item { Layout.fillWidth: true }
            RowLayout {
              spacing: Style.space(4)
              Button {
                iconText: "󰑐"
                tooltipText: "Refresh Lab status"
                focusable: true
                foreground: root.foreground
                background: "transparent"
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.labelGap
                Accessible.role: Accessible.Button
                Accessible.name: tooltipText
                enabled: !root.busy
                onClicked: root.refreshAll()
              }
              Button {
                iconText: "󰅖"
                tooltipText: "Close Lab controls"
                focusable: true
                foreground: root.foreground
                background: "transparent"
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.labelGap
                Accessible.role: Accessible.Button
                Accessible.name: tooltipText
                onClicked: root.dismiss()
              }
            }
          }

          ButtonGroup {
            Layout.alignment: Qt.AlignHCenter
            options: root.pageOptions
            value: root.pageOptions[root.currentPage]
            foreground: root.foreground
            background: "transparent"
            onChanged: function(value) { root.pageChanged(value) }
          }

          Text { visible: root.errorText !== "" && !root.inlineInstallError; text: root.errorText; textFormat: Text.PlainText; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; wrapMode: Text.WordWrap; Layout.fillWidth: true }

          QQC.ScrollView {
            id: pageScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: root.currentPageHeight
            Layout.maximumHeight: root.currentPageHeight
            Layout.minimumHeight: Math.min(root.currentPageHeight, Style.space(120))
            clip: true
            QQC.ScrollBar.horizontal.policy: QQC.ScrollBar.AlwaysOff

            ColumnLayout {
              width: pageScroll.availableWidth
              spacing: Style.space(12)

              ColumnLayout {
                id: consolePage
                visible: root.currentPage === 0
                Layout.fillWidth: true
                spacing: Style.space(12)

                ActionButton {
                  visible: root.status.installed
                  text: root.busy && root.actionLabel === "Opening Lab" ? "Opening Lab…" : "Open Lab"
                  onClicked: root.openLab()
                }

                WorkbenchSection {
                  visible: !root.status.installed
                  title: "Install the guest"
                  subtitle: "Creates a disposable VM; a terminal opens for setup and authentication"
                  ActionButton {
                    text: root.installerOpening ? "Opening installer…" : "Install Lab VM"
                    onClicked: root.openInstaller()
                  }
                  Text {
                    Layout.fillWidth: true
                    visible: root.inlineInstallError
                    text: root.errorText
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                  }
                }

                WorkbenchSection {
                  title: "Aspect ratio"
                  subtitle: "Resize the guest and viewer together"
                  ButtonGroup { Layout.fillWidth: true; options: root.aspectOptions; value: root.status.aspect; foreground: root.foreground; background: "transparent"; onChanged: function(value) { root.runViewer(["aspect", value], "Aspect ratio") } }
                }

                WorkbenchSection {
                  title: "Zoom"
                  subtitle: "Scale content while preserving its shape"
                  ButtonGroup { Layout.fillWidth: true; options: root.zoomOptions.map(function(value) { return { value: value, label: value + "%" } }); value: String(root.status.zoom); foreground: root.foreground; background: "transparent"; onChanged: function(value) { root.runViewer(["set", "zoom", value], "Zoom") } }
                }

                WorkbenchSection {
                  title: "Viewer"
                  subtitle: "Preferences persist between sessions"
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton { text: "Auto resize"; selected: root.status.autoResize; onClicked: root.runViewer(["set", "auto-resize", root.status.autoResize ? "false" : "true"], "Auto resize") }
                    ActionButton { text: "Local cursor"; selected: root.status.cursor === "local"; onClicked: root.runViewer(["set", "cursor", root.status.cursor === "local" ? "auto" : "local"], "Cursor") }
                    ActionButton { text: "Audio"; selected: root.status.audio; onClicked: root.runViewer(["set", "audio", root.status.audio ? "false" : "true"], "Audio") }
                    ActionButton { text: "USB"; selected: root.status.usbRedirection; onClicked: root.runViewer(["set", "usb-redirection", root.status.usbRedirection ? "false" : "true"], "USB redirection") }
                    ActionButton { text: "Keep in bar"; selected: root.status.keepInBar; onClicked: root.runViewer(["set", "keep-in-bar", root.status.keepInBar ? "false" : "true"], "Menu bar pin") }
                  }
                }

                WorkbenchSection {
                  title: "Console actions"
                  subtitle: "Reset requires a second confirmation"
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton { text: "Fullscreen"; onClicked: root.runViewer(["fullscreen"], "Fullscreen") }
                    ActionButton { text: "Screenshot"; onClicked: root.runViewer(["screenshot"], "Screenshot") }
                    ActionButton { text: "Reboot"; onClicked: root.runViewer(["reboot"], "Reboot") }
                    ActionButton { text: "Stop"; danger: true; onClicked: root.runViewer(["stop"], "Stop", true) }
                    ActionButton { text: root.terminalButtonText("reset", root.armedAction === "reset" ? "Confirm reset" : "Reset"); danger: true; onClicked: root.armOrRun("reset", root.viewerCommand, ["reset"], "reset") }
                  }
                }
              }

              ColumnLayout {
                id: developPage
                visible: root.currentPage === 1
                Layout.fillWidth: true
                spacing: Style.space(12)

                WorkbenchSection {
                  title: "Health dashboard"
                  subtitle: root.healthSummary
                  RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: "Refresh health"; onClicked: root.startProcess(healthProc) }
                    ActionButton { text: "Diagnostics"; onClicked: root.runCommand("omarchy-lab-capture", ["bundle"], "Diagnostic bundle") }
                  }
                }

                WorkbenchSection {
                  title: "Branch deployment"
                  subtitle: root.deploymentSummary
                  SearchableDropdown {
                    id: branchDropdown
                    Layout.fillWidth: true
                    showLabel: false
                    placeholderText: "Search local branches…"
                    emptyText: "No local branches"
                    triggerLabel: "Choose a local branch"
                    options: root.branches
                    value: root.selectedBranch
                    foreground: root.foreground
                    background: Color.popups.background
                    onChanged: function(value) { root.selectedBranch = value }
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: "Deploy branch + reboot"; enabled: !root.busy && root.selectedBranch !== ""; onClicked: root.runCommand("omarchy-lab-checkout", ["deploy", "--branch", root.selectedBranch], "Deploy branch") }
                    ActionButton { text: "Sync branch"; onClicked: root.runCommand("omarchy-lab-checkout", ["sync"], "Sync branch") }
                  }
                }

                WorkbenchSection {
                  title: "Named checkpoints"
                  subtitle: root.checkpoints.length + " saved · disk consistent"
                  RowLayout {
                    Layout.fillWidth: true
                    TextField { id: checkpointNameField; Layout.fillWidth: true; placeholderText: "checkpoint name"; foreground: root.foreground; accent: Color.accent }
                    ActionButton { Layout.fillWidth: false; text: "Create"; onClicked: root.runCommand("omarchy-lab-checkpoint", ["create"].concat(checkpointNameField.text === "" ? [] : [checkpointNameField.text]), "Create checkpoint") }
                  }
                  Dropdown { id: checkpointDropdown; Layout.fillWidth: true; showLabel: false; options: root.checkpoints; value: root.selectedCheckpoint; foreground: root.foreground; background: Color.popups.background; onChanged: function(value) { root.selectedCheckpoint = value } }
                  RowLayout {
                    Layout.fillWidth: true
                    TextField { id: checkpointRenameField; Layout.fillWidth: true; placeholderText: "new name"; foreground: root.foreground; accent: Color.accent }
                    ActionButton { Layout.fillWidth: false; text: "Rename"; enabled: !root.busy && root.selectedCheckpoint !== "" && checkpointRenameField.text !== ""; onClicked: root.runCommand("omarchy-lab-checkpoint", ["rename", root.selectedCheckpoint, checkpointRenameField.text], "Rename checkpoint") }
                    ActionButton { Layout.fillWidth: false; text: root.armedAction === "restore" ? "Confirm restore" : "Restore"; danger: true; enabled: !root.busy && root.selectedCheckpoint !== ""; onClicked: root.armOrRun("restore", "omarchy-lab-checkpoint", ["restore", root.selectedCheckpoint, "--yes"], "restore") }
                    ActionButton { Layout.fillWidth: false; text: root.armedAction === "delete-checkpoint" ? "Confirm delete" : "Delete"; danger: true; enabled: !root.busy && root.selectedCheckpoint !== ""; onClicked: root.armOrRun("delete-checkpoint", "omarchy-lab-checkpoint", ["delete", root.selectedCheckpoint, "--yes"], "delete") }
                  }
                }
              }

              ColumnLayout {
                id: environmentPage
                visible: root.currentPage === 2
                Layout.fillWidth: true
                spacing: Style.space(12)

                WorkbenchSection {
                  title: "Network mode"
                  subtitle: root.networkSummary
                  RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: "NAT"; onClicked: root.runCommand("omarchy-lab-network", ["nat"], "NAT network") }
                    ActionButton { text: "Isolated"; onClicked: root.runCommand("omarchy-lab-network", ["isolated"], "Isolated network") }
                    ActionButton { text: "Offline"; danger: true; onClicked: root.runCommand("omarchy-lab-network", ["offline"], "Offline network") }
                  }
                }

                WorkbenchSection {
                  title: "Resource profile"
                  subtitle: "Current: " + root.resourceSummary + " · changes restart the guest"
                  Text {
                    Layout.fillWidth: true
                    text: Model.resourceLimitsText(root.resources)
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton {
                      text: "Light · " + root.lightResources.cpus + " cores · " + root.lightResources.memoryGiB + " GiB"
                      tooltipText: "For quick checks and lightweight testing"
                      selected: root.resources.profile === "light"
                      enabled: root.resources.available && !root.busy
                      onClicked: root.setResourceProfile("light", "Light")
                    }
                    ActionButton {
                      text: "Balanced (recommended) · " + root.balancedResources.cpus + " cores · " + root.balancedResources.memoryGiB + " GiB"
                      tooltipText: "Recommended for most development and UI testing"
                      selected: root.resources.profile === "balanced"
                      enabled: root.resources.available && !root.busy
                      onClicked: root.setResourceProfile("balanced", "Balanced")
                    }
                    ActionButton {
                      text: "Performance · " + root.performanceResources.cpus + " cores · " + root.performanceResources.memoryGiB + " GiB"
                      tooltipText: "Extra room for heavier builds and multitasking"
                      selected: root.resources.profile === "performance"
                      enabled: root.resources.available && !root.busy
                      onClicked: root.setResourceProfile("performance", "Performance")
                    }
                    ActionButton {
                      text: "Full · " + root.fullResources.cpus + " cores · " + root.fullResources.memoryGiB + " GiB"
                      tooltipText: "High-performance Lab allocation; Custom can go higher"
                      selected: root.resources.profile === "full"
                      enabled: root.resources.available && !root.busy
                      onClicked: root.setResourceProfile("full", "Full")
                    }
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(12)
                    NumberField {
                      id: customCpuField
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignBottom
                      fieldWidth: width
                      label: "CPU cores (1–" + root.maximumResourceCpus + ")"
                      from: 1
                      to: root.maximumResourceCpus
                      value: root.customResourceCpus
                      enabled: root.resources.available && !root.busy
                      foreground: root.foreground
                      accent: Color.accent
                      fontFamily: Style.font.family
                      onModified: function(value) {
                        root.customResourceCpus = value
                        root.customResourcesDirty = true
                      }
                    }
                    NumberField {
                      id: customMemoryField
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignBottom
                      fieldWidth: width
                      label: "RAM in GiB (1–" + root.maximumResourceMemoryGiB + ")"
                      from: 1
                      to: root.maximumResourceMemoryGiB
                      value: root.customResourceMemoryGiB
                      enabled: root.resources.available && !root.busy
                      foreground: root.foreground
                      accent: Color.accent
                      fontFamily: Style.font.family
                      onModified: function(value) {
                        root.customResourceMemoryGiB = value
                        root.customResourcesDirty = true
                      }
                    }
                    ActionButton {
                      Layout.fillWidth: false
                      Layout.alignment: Qt.AlignBottom
                      text: "Apply custom"
                      selected: root.resources.profile === "custom" && !root.customResourcesDirty
                      enabled: root.resources.available && !root.busy
                      onClicked: root.applyCustomResources()
                    }
                  }
                }

                WorkbenchSection {
                  title: "Gold image"
                  subtitle: root.goldSummary
                  RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: root.terminalButtonText("promote", root.armedAction === "promote" ? "Confirm promote" : "Promote current"); danger: true; onClicked: root.armOrRun("promote", "omarchy-lab-gold", ["promote", "--yes"], "promote") }
                    ActionButton { text: root.terminalButtonText("rebuild", root.armedAction === "rebuild" ? "Confirm rebuild" : "Rebuild from ISO"); danger: true; onClicked: root.armOrRun("rebuild", "omarchy-lab-gold", ["rebuild", "--yes"], "rebuild") }
                  }
                }
              }

              ColumnLayout {
                id: capturePage
                visible: root.currentPage === 3
                Layout.fillWidth: true
                spacing: Style.space(12)

                WorkbenchSection {
                  title: "Artifact capture"
                  subtitle: root.artifactSummary
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 4
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton { text: "Screenshot"; onClicked: root.runCommand("omarchy-lab-capture", ["screenshot", "--copy"], "Screenshot") }
                    ActionButton { text: "Record 10s"; onClicked: root.recordViewer() }
                    ActionButton { text: "Diagnostics"; onClicked: root.runCommand("omarchy-lab-capture", ["bundle", "--copy"], "Diagnostic bundle") }
                    ActionButton { text: "Compare latest"; onClicked: root.runCommand("omarchy-lab-capture", ["compare", "--copy"], "Screenshot comparison") }
                  }
                }

                WorkbenchSection {
                  title: "Clipboard and files"
                  subtitle: "Explicit one-shot transfers; no shared host folders"
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton { text: "Host clipboard → guest"; onClicked: root.runCommand("omarchy-lab-transfer", ["clipboard-to", "--host"], "Send clipboard") }
                    ActionButton { text: "Guest clipboard → host"; onClicked: root.runCommand("omarchy-lab-transfer", ["clipboard-from", "--copy"], "Receive clipboard") }
                    ActionButton { text: "Choose files → guest"; onClicked: root.runCommand("omarchy-lab-transfer", ["pick-to"], "Send files") }
                    ActionButton { text: "Guest Downloads → host"; onClicked: root.runCommand("omarchy-lab-transfer", ["pull-downloads"], "Pull Downloads") }
                  }
                }
              }

              ColumnLayout {
                id: automatePage
                visible: root.currentPage === 4
                Layout.fillWidth: true
                spacing: Style.space(12)

                WorkbenchSection {
                  title: "Guest shortcuts"
                  subtitle: "Drive the graphical session without touching the console"
                  GridLayout {
                    Layout.fillWidth: true
                    columns: 3
                    columnSpacing: Style.space(8)
                    rowSpacing: Style.space(8)
                    ActionButton { text: "Terminal"; onClicked: root.runCommand("omarchy-lab-action", ["terminal"], "Open terminal") }
                    ActionButton { text: "Launcher"; onClicked: root.runCommand("omarchy-lab-action", ["launcher"], "Open launcher") }
                    ActionButton { text: "Lock"; onClicked: root.runCommand("omarchy-lab-action", ["lock"], "Lock guest") }
                    ActionButton { text: "Wake"; onClicked: root.runCommand("omarchy-lab-action", ["wake"], "Wake guest") }
                    ActionButton { text: "Restart shell"; onClicked: root.runCommand("omarchy-lab-action", ["restart-shell"], "Restart shell") }
                    ActionButton { text: "Reload Hyprland"; onClicked: root.runCommand("omarchy-lab-action", ["reload-hyprland"], "Reload Hyprland") }
                  }
                  RowLayout {
                    Layout.fillWidth: true
                    TextField { id: guestCommandField; Layout.fillWidth: true; placeholderText: "graphical-session command"; foreground: root.foreground; accent: Color.accent }
                    ActionButton { Layout.fillWidth: false; text: "Run"; enabled: !root.busy && guestCommandField.text !== ""; onClicked: root.runCommand("omarchy-lab-action", ["run", guestCommandField.text], "Guest command") }
                  }
                }

                WorkbenchSection {
                  title: "Scenario runner"
                  subtitle: "Validated command arrays; shell strings are never evaluated"
                  Dropdown { id: scenarioDropdown; Layout.fillWidth: true; showLabel: false; options: root.scenarios; value: root.selectedScenario; foreground: root.foreground; background: Color.popups.background; onChanged: function(value) { root.selectedScenario = value } }
                  RowLayout {
                    Layout.fillWidth: true
                    ActionButton { text: "Run scenario"; enabled: !root.busy && root.selectedScenario !== "" && (root.selectedScenario !== "checkpoint-deploy" || root.selectedBranch !== ""); onClicked: root.runCommand("omarchy-lab-scenario", ["run", root.selectedScenario].concat(root.selectedScenario === "checkpoint-deploy" ? [root.selectedBranch, "--branch"] : []), "Scenario " + root.selectedScenario) }
                  }
                }
              }
            }
          }

          Text { visible: root.busy || root.actionOutput !== ""; text: root.busy ? root.actionLabel + "…" : root.actionOutput; textFormat: Text.PlainText; color: root.busy ? Color.accent : root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle; maximumLineCount: 2; wrapMode: Text.Wrap; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
          Text { text: "Drag header · Alt+arrows move · Alt+Home centers · Ctrl+←/→ pages · Esc closes"; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; Layout.alignment: Qt.AlignHCenter }
        }
      }
    }
  }

  component WorkbenchSection: BorderSurface {
    required property string title
    required property string subtitle
    default property alias sectionContent: sectionBody.data
    Layout.fillWidth: true
    implicitHeight: sectionColumn.implicitHeight + Style.space(24)
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)
    radius: Style.cornerRadius
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

    ColumnLayout {
      id: sectionColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(12)
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        Text { text: parent.parent.parent.title; textFormat: Text.PlainText; color: root.foreground; font.family: Style.font.family; font.pixelSize: Style.font.subtitle; font.bold: true }
        Text { Layout.fillWidth: true; text: parent.parent.parent.subtitle; textFormat: Text.PlainText; color: root.dim; font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle; horizontalAlignment: Text.AlignRight }
      }
      ColumnLayout { id: sectionBody; Layout.fillWidth: true; spacing: Style.space(8) }
    }
  }

  component ActionButton: Button {
    property bool danger: false
    Layout.fillWidth: true
    focusable: true
    bordered: true
    foreground: danger ? Color.urgent : root.foreground
    background: "transparent"
    enabled: !root.busy
  }
}
