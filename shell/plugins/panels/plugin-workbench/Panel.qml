import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.plugin-workbench"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string helperPath: ""
  property var projects: []
  property var pluginUpdates: []
  property var installedPlugins: []
  property string installedQuery: ""
  property bool updatesChecked: false
  property bool portfolioLoaded: false
  property string viewMode: "discover"
  property bool marketplaceLoaded: false
  property var marketplaceResults: []
  property int marketplaceMatched: 0
  property int marketplaceTotal: 0
  property string marketplaceGeneratedAt: ""
  property bool marketplaceBuiltInsOnly: false
  property bool marketplaceVerifiedOnly: false
  property bool marketplaceInstallableOnly: false
  property bool marketplaceInstalledOnly: false
  property string marketplaceConfirmation: ""
  property string message: ""
  property bool messageError: false
  property string refreshOutput: ""
  property string portfolioOutput: ""
  property string actionOutput: ""
  property string actionError: ""
  property bool showBuilderSetup: false
  property bool createProjectOpen: true
  property string newPluginKind: "panel"
  property string pendingAction: ""
  readonly property int projectCount: projects.length
  readonly property bool buildOpen: viewMode === "build"
  readonly property bool installedOpen: viewMode === "installed"
  readonly property bool marketplaceOpen: viewMode === "discover"
  readonly property bool updatesOpen: viewMode === "updates"
  readonly property int availableUpdateCount: pluginUpdates.filter(function(plugin) { return plugin.updateable }).length
  readonly property int marketplaceUpdateCount: installedPlugins.filter(function(plugin) {
    return plugin.management === "marketplace" && plugin.updateAvailable
  }).length
  readonly property int totalUpdateCount: availableUpdateCount + marketplaceUpdateCount
  readonly property var reviewUpdateRows: pluginUpdates.filter(function(plugin) {
    return plugin.state !== "up-to-date"
  }).map(function(update) {
    return { kind: "git", update: update, plugin: null }
  }).concat(installedPlugins.filter(function(plugin) {
    return plugin.management === "marketplace" && plugin.updateAvailable
  }).map(function(plugin) {
    return { kind: "marketplace", update: null, plugin: plugin }
  }))
  readonly property var installedRows: installedPlugins.map(function(plugin) {
    var update = null
    for (var index = 0; index < pluginUpdates.length; index += 1) {
      if (pluginUpdates[index].id === plugin.id) {
        update = pluginUpdates[index]
        break
      }
    }
    return { plugin: plugin, update: update }
  })
  readonly property int installedCount: installedRows.length
  readonly property var visibleInstalledRows: installedRows.filter(function(row) {
    var query = root.installedQuery.trim().toLowerCase()
    if (!query) return true
    var plugin = row.plugin
    return String(plugin.name || "").toLowerCase().indexOf(query) !== -1
      || String(plugin.id || "").toLowerCase().indexOf(query) !== -1
      || String(plugin.management || "").toLowerCase().indexOf(query) !== -1
  })
  readonly property bool busy: refreshProcess.running || portfolioProcess.running || actionProcess.running
  readonly property color surfaceSubtle: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.055)
  readonly property color borderSubtle: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.16)
  readonly property color textMuted: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
  readonly property color accentWash: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)

  function open() {
    root.controller.show()
    refreshView()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refresh() {
    if (!root.helperPath || refreshProcess.running) return
    root.refreshOutput = ""
    refreshProcess.command = [root.helperPath, "status", "--json"]
    refreshProcess.running = true
  }

  function refreshView() {
    if (root.buildOpen) refresh()
    else if (root.installedOpen) loadPortfolio()
    else if (root.updatesOpen) refreshUpdates()
    else refreshMarketplace()
  }

  function setViewMode(mode) {
    if (root.busy || root.viewMode === mode) return
    root.viewMode = mode
    root.marketplaceConfirmation = ""
    if (mode === "installed") loadPortfolio()
    else if (mode === "updates") refreshUpdates()
    else if (mode === "discover") {
      if (root.marketplaceLoaded) searchMarketplace()
      else refreshMarketplace()
    } else refresh()
  }

  function refreshInstalled() {
    checkUpdates()
    loadPortfolio()
  }

  function refreshUpdates() {
    checkUpdates()
    loadPortfolio()
  }

  function loadPortfolio() {
    if (!root.helperPath || portfolioProcess.running) return
    root.portfolioOutput = ""
    portfolioProcess.command = [root.helperPath, "installed", "--json"]
    portfolioProcess.running = true
  }

  function applyPortfolio() {
    try {
      var parsed = JSON.parse(root.portfolioOutput || "{}")
      root.installedPlugins = Array.isArray(parsed.plugins) ? parsed.plugins : []
      root.portfolioLoaded = true
    } catch (error) {
      root.message = "Could not parse installed plugin portfolio: " + error
      root.messageError = true
    }
  }

  function applyRefresh() {
    try {
      var parsed = JSON.parse(root.refreshOutput || "[]")
      root.projects = Array.isArray(parsed) ? parsed : []
      if (!Array.isArray(parsed)) {
        root.message = parsed.error || "Unexpected status response"
        root.messageError = true
      }
    } catch (error) {
      root.message = "Could not parse Workbench status: " + error
      root.messageError = true
    }
  }

  function runAction(action, projectId) {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = action + " · " + projectId
    root.messageError = false
    root.pendingAction = "project"
    actionProcess.command = [root.helperPath, action, projectId, "--json"]
    actionProcess.running = true
  }

  function runInstalledAction(action, pluginId) {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = (action === "installed-enable" ? "Enabling " : "Disabling ") + pluginId + "…"
    root.messageError = false
    root.pendingAction = "installed"
    actionProcess.command = [root.helperPath, action, pluginId, "--json"]
    actionProcess.running = true
  }

  function addProject() {
    var path = String(pathInput.text || "").trim()
    if (!path || root.busy) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Registering " + path
    root.messageError = false
    root.pendingAction = "project"
    actionProcess.command = [root.helperPath, "add", path, "--json"]
    actionProcess.running = true
  }

  function createProject() {
    var path = String(newPathInput.text || "").trim()
    var id = String(newIdInput.text || "").trim()
    var name = String(newNameInput.text || "").trim()
    if (!path || !id || !name || root.busy) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Creating " + name + "…"
    root.messageError = false
    root.pendingAction = "new"
    actionProcess.command = [root.helperPath, "new", path, "--id", id,
      "--name", name, "--kind", root.newPluginKind, "--json"]
    actionProcess.running = true
  }

  function activeFeed() {
    return root.marketplaceOpen ? marketplaceList
      : root.installedOpen ? installedList
      : root.updatesOpen ? updateList : projectList
  }

  function scrollFeed(amount) {
    var feed = activeFeed()
    var minimum = feed.originY
    var maximum = minimum + Math.max(0, feed.contentHeight - feed.height)
    feed.contentY = Math.max(minimum, Math.min(maximum, feed.contentY + amount))
  }

  function scrollFeedEdge(end) {
    var feed = activeFeed()
    feed.contentY = end
      ? feed.originY + Math.max(0, feed.contentHeight - feed.height)
      : feed.originY
  }

  function checkUpdates() {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Fetching installed plugin updates…"
    root.messageError = false
    root.pendingAction = "updates"
    actionProcess.command = [root.helperPath, "updates", "--json"]
    actionProcess.running = true
  }

  function applyUpdate(pluginId, revision) {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Updating " + pluginId + " through Omarchy…"
    root.messageError = false
    root.pendingAction = "update"
    actionProcess.command = [root.helperPath, "update", pluginId, "--revision", revision, "--yes", "--json"]
    actionProcess.running = true
  }

  function applyAllUpdates() {
    if (root.busy || !root.helperPath || root.availableUpdateCount === 0) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Applying " + root.availableUpdateCount + " reviewed update(s)…"
    root.messageError = false
    root.pendingAction = "update"
    var command = [root.helperPath, "update-all", "--yes", "--json"]
    root.pluginUpdates.filter(function(plugin) { return plugin.updateable }).forEach(function(plugin) {
      command.push("--reviewed")
      command.push(plugin.id + "=" + plugin.remoteRevision)
    })
    actionProcess.command = command
    actionProcess.running = true
  }

  function incomingSummary(commits) {
    if (!Array.isArray(commits) || commits.length === 0) return "No incoming commit summary"
    return commits.slice(0, 5).map(function(commit) {
      return commit.revision + "  " + commit.subject
    }).join("\n") + (commits.length > 5 ? "\n…" : "")
  }

  function refreshMarketplace() {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Refreshing the official marketplace catalogue…"
    root.messageError = false
    root.pendingAction = "marketplace-refresh"
    actionProcess.command = [root.helperPath, "marketplace-refresh", "--json"]
    actionProcess.running = true
  }

  function searchMarketplace() {
    if (root.busy || !root.helperPath) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Searching the cached marketplace…"
    root.messageError = false
    root.pendingAction = "marketplace-search"
    var command = [root.helperPath, "marketplace-search"]
    var query = String(marketplaceSearchInput.text || "").trim()
    if (query) command.push(query)
    if (root.marketplaceBuiltInsOnly) command.push("--built-in")
    if (root.marketplaceVerifiedOnly) command.push("--verified")
    if (root.marketplaceInstallableOnly) command.push("--installable")
    if (root.marketplaceInstalledOnly) command.push("--installed")
    command.push("--limit")
    command.push("50")
    command.push("--json")
    actionProcess.command = command
    actionProcess.running = true
  }

  function installMarketplace(plugin) {
    if (root.busy || !root.helperPath || !plugin.installable) return
    root.actionOutput = ""
    root.actionError = ""
    root.message = "Installing reviewed snapshot of " + plugin.name + "…"
    root.messageError = false
    root.pendingAction = "marketplace-install"
    actionProcess.command = [root.helperPath, "marketplace-install", plugin.id,
      "--repo", plugin.repo, "--revision", plugin.reviewedRevision,
      "--enable", "--yes", "--json"]
    actionProcess.running = true
  }

  function updateMarketplace(plugin) {
    if (root.busy || !root.helperPath || !plugin.managed || !plugin.updateAvailable) return
    root.pendingAction = "marketplace-update"
    root.message = "Applying reviewed marketplace update for " + plugin.name + "…"
    root.messageError = false
    actionProcess.command = [root.helperPath, "marketplace-update", plugin.id,
      "--revision", plugin.reviewedRevision, "--yes", "--json"]
    actionProcess.running = true
  }

  function updateManagedPlugin(plugin) {
    if (root.busy || !root.helperPath || !plugin.updateAvailable || !plugin.catalogueRevision) return
    root.pendingAction = "marketplace-update"
    root.message = "Applying reviewed marketplace update for " + plugin.id + "…"
    root.messageError = false
    actionProcess.command = [root.helperPath, "marketplace-update", plugin.id,
      "--revision", plugin.catalogueRevision, "--yes", "--json"]
    actionProcess.running = true
  }

  function confirmedMarketplaceAction(action, plugin) {
    var key = action + ":" + plugin.id
    var displayName = plugin.name || plugin.id
    if (root.marketplaceConfirmation !== key) {
      root.marketplaceConfirmation = key
      root.message = "Click “Confirm " + action + "” again for " + displayName
      root.messageError = false
      return
    }
    root.marketplaceConfirmation = ""
    root.pendingAction = "marketplace-" + action
    root.message = (action === "repair" ? "Repairing " : "Uninstalling ") + displayName + "…"
    actionProcess.command = [root.helperPath, "marketplace-" + action, plugin.id, "--yes", "--json"]
    actionProcess.running = true
  }

  function completeAction(exitCode) {
    var text = String(root.actionOutput || "").trim()
    var errorText = String(root.actionError || "").trim()
    var parsed = null
    try { parsed = JSON.parse(text || errorText || "{}") } catch (error) {}
    if (root.pendingAction === "marketplace-refresh" && exitCode === 0 && parsed && parsed.ok) {
      root.marketplaceLoaded = true
      root.marketplaceGeneratedAt = parsed.generatedAt || ""
      root.message = parsed.message || "Marketplace catalogue refreshed"
      root.messageError = false
      root.pendingAction = ""
      Qt.callLater(root.searchMarketplace)
      return
    }
    if (root.pendingAction === "marketplace-search" && exitCode === 0 && parsed && Array.isArray(parsed.plugins)) {
      root.marketplaceLoaded = true
      root.marketplaceResults = parsed.plugins
      root.marketplaceMatched = Number(parsed.matched || 0)
      root.marketplaceTotal = Number(parsed.total || 0)
      root.marketplaceGeneratedAt = parsed.generatedAt || root.marketplaceGeneratedAt
      root.message = root.marketplaceMatched + " marketplace result(s)"
      root.messageError = false
      root.pendingAction = ""
      return
    }
    if (root.pendingAction === "updates" && exitCode === 0 && parsed && Array.isArray(parsed.plugins)) {
      root.pluginUpdates = parsed.plugins
      root.updatesChecked = true
      root.message = Number(parsed.available || 0) + " update(s) available"
        + (Number(parsed.blocked || 0) > 0 ? " · " + parsed.blocked + " need attention" : "")
      root.messageError = false
      root.pendingAction = ""
      return
    }
    root.messageError = exitCode !== 0 || (parsed && parsed.ok === false)
    root.message = parsed && parsed.error ? parsed.error
      : parsed && parsed.message ? parsed.message
      : errorText || text || (exitCode === 0 ? "Action completed" : "Action failed")
    if (exitCode === 0) {
      pathInput.text = ""
      if (root.pendingAction === "new") {
        newNameInput.text = ""
        newIdInput.text = ""
        newPathInput.text = ""
      }
      if (root.pendingAction === "update") Qt.callLater(root.refreshInstalled)
      else if (root.pendingAction === "installed") Qt.callLater(root.refreshInstalled)
      else if (root.pendingAction.indexOf("marketplace-") === 0) {
        if (root.marketplaceOpen) Qt.callLater(root.searchMarketplace)
        else Qt.callLater(root.refreshInstalled)
      }
      else Qt.callLater(root.refresh)
    }
    root.pendingAction = ""
  }

  Process {
    id: refreshProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.refreshOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim()) {
          root.message = String(text).trim()
          root.messageError = true
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) Qt.callLater(root.applyRefresh)
      else {
        root.message = root.message || "Workbench helper could not load projects"
        root.messageError = true
      }
    }
  }

  Process {
    id: portfolioProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.portfolioOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (String(text || "").trim()) {
          root.message = String(text).trim()
          root.messageError = true
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0) Qt.callLater(root.applyPortfolio)
      else {
        root.message = root.message || "Installed plugin portfolio could not be loaded"
        root.messageError = true
      }
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionOutput = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.actionError = String(text || "")
    }
    onExited: function(exitCode) {
      Qt.callLater(function() { root.completeAction(exitCode) })
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(720))
    contentHeight: panel.fittedContentHeight(Style.space(540))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Keys.onPressed: function(event) {
        if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_1) {
          root.setViewMode("discover")
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_2) {
          root.setViewMode("installed")
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_3) {
          root.setViewMode("updates")
        } else if (event.modifiers === Qt.ControlModifier && event.key === Qt.Key_4) {
          root.setViewMode("build")
        } else if (event.modifiers !== Qt.NoModifier) {
          return
        } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
          root.scrollFeed(Style.space(56))
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
          root.scrollFeed(-Style.space(56))
        } else if (event.key === Qt.Key_PageDown) {
          root.scrollFeed(root.activeFeed().height * 0.82)
        } else if (event.key === Qt.Key_PageUp) {
          root.scrollFeed(-root.activeFeed().height * 0.82)
        } else if (event.key === Qt.Key_Home) {
          root.scrollFeedEdge(false)
        } else if (event.key === Qt.Key_End) {
          root.scrollFeedEdge(true)
        } else {
          return
        }
        event.accepted = true
      }

      Rectangle {
        anchors.fill: parent
        color: root.bar ? root.bar.background : Color.background

        Column {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          spacing: Style.space(10)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Column {
              width: parent.width - refreshButton.width - Style.space(8)
              spacing: Style.space(2)

              Text {
                text: "OMARCHY PLUGIN WORKBENCH"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: root.marketplaceOpen
                  ? root.marketplaceMatched + " of " + root.marketplaceTotal + " official catalogue listings"
                  : root.installedOpen
                    ? root.installedCount + " plugins discovered by Omarchy"
                    : root.updatesOpen
                      ? root.totalUpdateCount + " reviewed plugin updates ready"
                      : "Build and test personal plugins without leaving the shell"
                color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.62)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            WorkbenchButton {
              id: refreshButton
              label: root.busy ? "Working…" : "Refresh"
              enabled: !root.busy
              onTriggered: root.refreshView()
            }
          }

          Row {
            id: lifecycleRail
            width: parent.width
            height: Style.space(48)
            spacing: Style.space(6)

            ModeTab {
              width: (lifecycleRail.width - Style.space(18)) / 4
              title: "1  DISCOVER"
              detail: root.marketplaceLoaded
                ? root.marketplaceTotal + " listings" : "Official catalogue"
              active: root.marketplaceOpen
              onTriggered: root.setViewMode("discover")
            }
            ModeTab {
              width: (lifecycleRail.width - Style.space(18)) / 4
              title: "2  INSTALLED"
              detail: root.installedCount + " plugins"
              active: root.installedOpen
              onTriggered: root.setViewMode("installed")
            }
            ModeTab {
              width: (lifecycleRail.width - Style.space(18)) / 4
              title: "3  UPDATES"
              detail: root.totalUpdateCount > 0
                ? root.totalUpdateCount + " ready" : "Review first"
              active: root.updatesOpen
              onTriggered: root.setViewMode("updates")
            }
            ModeTab {
              width: (lifecycleRail.width - Style.space(18)) / 4
              title: "4  BUILD"
              detail: root.projectCount + (root.projectCount === 1 ? " project" : " projects")
              active: root.buildOpen
              onTriggered: root.setViewMode("build")
            }
          }

          Rectangle {
            visible: root.buildOpen
            width: parent.width
            height: visible ? (root.createProjectOpen ? Style.space(124) : Style.space(82)) : 0
            color: "transparent"
            border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.28)
            border.width: 1
            radius: Style.cornerRadius

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(7)
              spacing: Style.space(6)

              Row {
                spacing: Style.space(6)
                WorkbenchButton {
                  label: root.createProjectOpen ? "New plugin ✓" : "New plugin"
                  onTriggered: root.createProjectOpen = true
                }
                WorkbenchButton {
                  label: root.createProjectOpen ? "Add existing" : "Add existing ✓"
                  onTriggered: root.createProjectOpen = false
                }
              }

              Row {
                visible: root.createProjectOpen
                height: visible ? Style.space(32) : 0
                width: parent.width
                spacing: Style.space(6)
                WorkbenchField {
                  id: newNameInput
                  width: parent.width * 0.34
                  placeholder: "Plugin name"
                }
                WorkbenchField {
                  id: newIdInput
                  width: parent.width * 0.66 - Style.space(6)
                  placeholder: "Plugin ID · io.github.you.plugin"
                }
              }

              Row {
                visible: root.createProjectOpen
                height: visible ? Style.space(32) : 0
                width: parent.width
                spacing: Style.space(6)
                WorkbenchField {
                  id: newPathInput
                  width: parent.width - kindPanel.width - kindWidget.width - kindService.width
                    - createButton.width - Style.space(24)
                  placeholder: "New absolute folder path"
                  onAccepted: root.createProject()
                }
                WorkbenchButton {
                  id: kindPanel
                  label: root.newPluginKind === "panel" ? "Panel ✓" : "Panel"
                  onTriggered: root.newPluginKind = "panel"
                }
                WorkbenchButton {
                  id: kindWidget
                  label: root.newPluginKind === "bar-widget" ? "Widget ✓" : "Widget"
                  onTriggered: root.newPluginKind = "bar-widget"
                }
                WorkbenchButton {
                  id: kindService
                  label: root.newPluginKind === "service" ? "Service ✓" : "Service"
                  onTriggered: root.newPluginKind = "service"
                }
                WorkbenchButton {
                  id: createButton
                  label: "Create"
                  enabled: !root.busy && String(newNameInput.text || "").trim() !== ""
                    && String(newIdInput.text || "").trim() !== ""
                    && String(newPathInput.text || "").trim() !== ""
                  onTriggered: root.createProject()
                }
              }

              Row {
                visible: !root.createProjectOpen
                height: visible ? Style.space(32) : 0
                width: parent.width
                spacing: Style.space(8)
                WorkbenchField {
                  id: pathInput
                  width: parent.width - addButton.width - Style.space(8)
                  placeholder: "Absolute path to an existing plugin project"
                  onAccepted: root.addProject()
                }
                WorkbenchButton {
                  id: addButton
                  label: "Register"
                  enabled: !root.busy && String(pathInput.text || "").trim() !== ""
                  onTriggered: root.addProject()
                }
              }
            }
          }

          Rectangle {
            visible: root.marketplaceOpen
            width: parent.width
            height: visible ? Style.space(38) : 0
            color: "transparent"
            border.color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.28)
            border.width: 1
            radius: Style.cornerRadius

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(7)
              spacing: Style.space(8)

              TextInput {
                id: marketplaceSearchInput
                width: parent.width - marketplaceSearchButton.width - marketplaceRefreshButton.width - Style.space(16)
                height: parent.height
                color: root.barForeground
                selectionColor: Color.accent
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                selectByMouse: true
                onAccepted: root.searchMarketplace()

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !marketplaceSearchInput.text
                  text: "Search name, description, author, category or tag"
                  color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.42)
                  font: marketplaceSearchInput.font
                }
              }

              WorkbenchButton {
                id: marketplaceSearchButton
                label: "Search"
                enabled: !root.busy && root.marketplaceLoaded
                onTriggered: root.searchMarketplace()
              }

              WorkbenchButton {
                id: marketplaceRefreshButton
                label: "Refresh"
                enabled: !root.busy
                onTriggered: root.refreshMarketplace()
              }
            }
          }

          Rectangle {
            visible: root.installedOpen
            width: parent.width
            height: visible ? Style.space(48) : 0
            color: "transparent"
            border.color: root.borderSubtle
            border.width: 1
            radius: Style.cornerRadius

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(8)
              WorkbenchField {
                id: installedSearchInput
                width: parent.width - installedCheck.width - Style.space(8)
                placeholder: "Search installed plugins or management source"
                onTextChanged: root.installedQuery = text
              }
              WorkbenchButton {
                id: installedCheck
                label: "Refresh"
                enabled: !root.busy
                onTriggered: root.loadPortfolio()
              }
            }
          }

          Rectangle {
            visible: root.updatesOpen
            width: parent.width
            height: visible ? Style.space(66) : 0
            color: root.accentWash
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.35)
            border.width: 1
            radius: Style.cornerRadius

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)
              Text {
                width: parent.width
                text: "Plugin updates are reviewed and applied to an exact revision · never unattended"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              Row {
                spacing: Style.space(6)
                WorkbenchButton {
                  visible: root.availableUpdateCount > 0
                  label: "Update Git plugins"
                  enabled: !root.busy
                  onTriggered: root.applyAllUpdates()
                }
                WorkbenchButton {
                  label: root.busy ? "Checking…" : "Check updates"
                  enabled: !root.busy
                  onTriggered: root.checkUpdates()
                }
              }
            }
          }

          Row {
            visible: root.marketplaceOpen
            height: visible ? implicitHeight : 0
            spacing: Style.space(6)
            WorkbenchButton {
              label: root.marketplaceBuiltInsOnly ? "Built-ins ✓" : "Built-ins"
              onTriggered: {
                root.marketplaceBuiltInsOnly = !root.marketplaceBuiltInsOnly
                root.searchMarketplace()
              }
            }
            WorkbenchButton {
              label: root.marketplaceVerifiedOnly ? "Verified ✓" : "Verified"
              onTriggered: {
                root.marketplaceVerifiedOnly = !root.marketplaceVerifiedOnly
                root.searchMarketplace()
              }
            }
            WorkbenchButton {
              label: root.marketplaceInstallableOnly ? "Installable ✓" : "Installable"
              onTriggered: {
                root.marketplaceInstallableOnly = !root.marketplaceInstallableOnly
                root.searchMarketplace()
              }
            }
            WorkbenchButton {
              label: root.marketplaceInstalledOnly ? "Installed ✓" : "Installed"
              onTriggered: {
                root.marketplaceInstalledOnly = !root.marketplaceInstalledOnly
                root.searchMarketplace()
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.marketplaceGeneratedAt ? "Catalogue " + root.marketplaceGeneratedAt.slice(0, 10) : ""
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.48)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          Rectangle {
            width: parent.width
            height: root.message ? Style.space(34) : 0
            visible: height > 0
            radius: Style.cornerRadius
            color: root.messageError
              ? Qt.rgba(0.72, 0.18, 0.18, 0.20)
              : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14)

            Text {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              text: root.message
              textFormat: Text.PlainText
              color: root.messageError ? Color.urgent : root.barForeground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              verticalAlignment: Text.AlignVCenter
            }
          }

          Item {
            width: parent.width
            height: parent.height - y

            ListView {
              id: marketplaceList
              anchors.fill: parent
              visible: root.marketplaceOpen
              clip: true
              spacing: Style.space(8)
              boundsBehavior: Flickable.StopAtBounds
              reuseItems: true
              cacheBuffer: height
              model: root.marketplaceResults

              delegate: MarketplaceCard {
                required property var modelData
                width: marketplaceList.width
                plugin: modelData
              }
            }

            Text {
              visible: root.marketplaceOpen && root.marketplaceLoaded
                && root.marketplaceResults.length === 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: Style.space(40)
              text: "No marketplace plugins match this search."
              color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            ListView {
              id: installedList
              anchors.fill: parent
              visible: root.installedOpen
              clip: true
              spacing: Style.space(8)
              boundsBehavior: Flickable.StopAtBounds
              reuseItems: true
              cacheBuffer: height
              model: root.visibleInstalledRows

              delegate: InstalledCard {
                required property var modelData
                width: installedList.width
                row: modelData
              }
            }

            ListView {
              id: updateList
              anchors.fill: parent
              visible: root.updatesOpen
              clip: true
              spacing: Style.space(8)
              boundsBehavior: Flickable.StopAtBounds
              reuseItems: true
              cacheBuffer: height
              model: root.reviewUpdateRows

              delegate: UpdateCard {
                required property var modelData
                width: updateList.width
                entry: modelData
              }

              footer: Column {
                visible: root.updatesChecked && root.portfolioLoaded
                  && root.reviewUpdateRows.length === 0
                width: updateList.width
                topPadding: Style.space(48)
                spacing: Style.space(8)
                Text {
                  width: parent.width
                  text: "Every reviewed plugin is current"
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  text: "Workbench will show exact revisions and blockers here when updates are available."
                  color: root.textMuted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
            }

            Column {
              visible: root.installedOpen && root.portfolioLoaded
                && root.visibleInstalledRows.length === 0
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: Style.space(48)
              spacing: Style.space(8)

              Text {
                width: parent.width
                text: root.installedQuery ? "No installed plugins match" : "No installed plugins found"
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
              }
              Text {
                width: parent.width
                text: "Refresh the shell inventory, install from Discover, or link a project from Build."
                color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }
            }

            ListView {
              id: projectList
              anchors.fill: parent
              visible: root.buildOpen
              clip: true
              spacing: Style.space(8)
              boundsBehavior: Flickable.StopAtBounds
              reuseItems: true
              cacheBuffer: height
              model: root.projects

              delegate: ProjectCard {
                required property var modelData
                width: projectList.width
                project: modelData
              }

              footer: Column {
                visible: root.projects.length === 0
                width: projectList.width
                topPadding: Style.space(48)
                spacing: Style.space(9)

                Text {
                  width: parent.width
                  text: "Create your first personal plugin"
                  color: root.barForeground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }

                Text {
                  width: parent.width
                  text: "Use New plugin above for a safe starter, or use Build Omarchy Plugins when you want an agent-guided custom build. Workbench never scans your home directory automatically."
                  color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }

                WorkbenchButton {
                  anchors.horizontalCenter: parent.horizontalCenter
                  label: root.showBuilderSetup ? "Hide setup" : "Builder setup"
                  onTriggered: root.showBuilderSetup = !root.showBuilderSetup
                }

                Rectangle {
                  visible: root.showBuilderSetup
                  width: parent.width
                  height: visible ? setupText.implicitHeight + Style.space(20) : 0
                  radius: Style.cornerRadius
                  color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10)

                  Text {
                    id: setupText
                    anchors.fill: parent
                    anchors.margins: Style.space(10)
                    text: "Install Build Omarchy Plugins in your preferred agent host, ask it to scaffold an Omarchy plugin, then paste the generated checkout path above.\n\ngithub.com/tcballard/build-omarchy-plugins"
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component WorkbenchButton: Rectangle {
    id: actionButton
    property string label: ""
    signal triggered()
    activeFocusOnTab: true
    implicitWidth: buttonLabel.implicitWidth + Style.space(18)
    implicitHeight: Style.space(28)
    radius: Style.cornerRadius
    border.color: activeFocus ? Color.accent : "transparent"
    border.width: 1
    color: buttonHover.hovered
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
      : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.09)
    opacity: enabled ? 1 : 0.45

    Text {
      id: buttonLabel
      anchors.centerIn: parent
      text: actionButton.label
      textFormat: Text.PlainText
      color: root.barForeground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    HoverHandler { id: buttonHover }
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        actionButton.triggered()
        event.accepted = true
      } else event.accepted = false
    }
    TapHandler {
      enabled: actionButton.enabled
      onTapped: {
        actionButton.forceActiveFocus()
        actionButton.triggered()
      }
    }
  }

  component ModeTab: Rectangle {
    id: modeTab
    property string title: ""
    property string detail: ""
    property bool active: false
    signal triggered()
    activeFocusOnTab: true
    implicitHeight: Style.space(48)
    color: modeTap.pressed
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.30)
      : modeHover.hovered ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
      : active ? root.accentWash : root.surfaceSubtle
    border.color: activeFocus ? Color.accent
      : active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.46) : root.borderSubtle
    border.width: 1
    radius: Style.cornerRadius

    Column {
      anchors.centerIn: parent
      spacing: Style.space(2)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: modeTab.title
        textFormat: Text.PlainText
        color: modeTab.active ? Color.accent : root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: modeTab.detail
        textFormat: Text.PlainText
        color: root.textMuted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
        modeTab.triggered()
        event.accepted = true
      } else event.accepted = false
    }
    HoverHandler { id: modeHover }
    TapHandler {
      id: modeTap
      enabled: !root.busy
      onTapped: {
        modeTab.forceActiveFocus()
        modeTab.triggered()
      }
    }
  }

  component WorkbenchField: Rectangle {
    id: field
    property alias text: fieldInput.text
    property string placeholder: ""
    signal accepted()
    implicitHeight: Style.space(32)
    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.055)
    border.color: fieldInput.activeFocus
      ? Color.accent : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)
    border.width: 1
    radius: Style.cornerRadius

    TextInput {
      id: fieldInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      color: root.barForeground
      selectionColor: Color.accent
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      selectByMouse: true
      onAccepted: field.accepted()

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !fieldInput.text
        text: field.placeholder
        textFormat: Text.PlainText
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.42)
        font: fieldInput.font
      }
    }
  }

  component InstalledCard: Rectangle {
    id: installedCard
    required property var row
    readonly property var plugin: row.plugin
    readonly property var update: row.update
    readonly property bool marketplaceManaged: plugin.management === "marketplace"
    readonly property bool updateReady: marketplaceManaged
      ? Boolean(plugin.updateAvailable) : Boolean(update && update.updateable)
    readonly property string state: marketplaceManaged
      ? String(plugin.managedState || "current")
      : update ? String(update.state || "unknown")
      : Boolean(plugin.enabled) ? "enabled" : "disabled"
    readonly property bool healthy: state === "up-to-date" || state === "current"
      || state === "enabled" || state === "disabled"
    readonly property string sourceLabel: plugin.management === "first-party" ? "OMARCHY"
      : plugin.management === "marketplace" ? "MARKETPLACE MANAGED"
      : plugin.management === "live-link" ? "LIVE DEVELOPMENT LINK"
      : plugin.management === "git" ? "DIRECT GIT CHECKOUT"
      : "LOCAL PLUGIN"
    implicitHeight: installedContent.implicitHeight + Style.space(18)
    color: root.surfaceSubtle
    radius: Style.cornerRadius
    border.color: updateReady
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.48)
      : healthy ? root.borderSubtle : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.42)
    border.width: 1

    Column {
      id: installedContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(9)
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - installedActions.width - Style.space(8)
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: installedCard.plugin.name || installedCard.plugin.id
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: installedCard.sourceLabel
              + "  ·  " + installedCard.state.replace(/-/g, " ").toUpperCase()
            textFormat: Text.PlainText
            color: installedCard.updateReady ? Color.accent
              : installedCard.healthy ? root.textMuted : Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Row {
          id: installedActions
          spacing: Style.space(5)
          WorkbenchButton {
            visible: !installedCard.marketplaceManaged && installedCard.updateReady
            label: "Update"
            enabled: !root.busy
            onTriggered: root.applyUpdate(installedCard.plugin.id, installedCard.update.remoteRevision)
          }
          WorkbenchButton {
            visible: installedCard.marketplaceManaged && installedCard.updateReady
            label: "Update"
            enabled: !root.busy
            onTriggered: root.updateManagedPlugin(installedCard.plugin)
          }
          WorkbenchButton {
            visible: !installedCard.plugin.enabled
            label: "Enable"
            enabled: !root.busy
            onTriggered: root.runInstalledAction("installed-enable", installedCard.plugin.id)
          }
          WorkbenchButton {
            visible: Boolean(installedCard.plugin.enabled) && Boolean(installedCard.plugin.canDisable)
            label: "Disable"
            enabled: !root.busy
            onTriggered: root.runInstalledAction("installed-disable", installedCard.plugin.id)
          }
          WorkbenchButton {
            visible: installedCard.marketplaceManaged
            label: root.marketplaceConfirmation === "repair:" + installedCard.plugin.id
              ? "Confirm repair" : "Repair"
            enabled: !root.busy
            onTriggered: root.confirmedMarketplaceAction("repair", installedCard.plugin)
          }
          WorkbenchButton {
            visible: installedCard.marketplaceManaged
            label: root.marketplaceConfirmation === "uninstall:" + installedCard.plugin.id
              ? "Confirm remove" : "Remove"
            enabled: !root.busy
            onTriggered: root.confirmedMarketplaceAction("uninstall", installedCard.plugin)
          }
        }
      }

      Text {
        width: parent.width
        text: installedCard.marketplaceManaged
          ? String(installedCard.plugin.installedRevision || "").slice(0, 10)
            + (installedCard.plugin.catalogueRevision
              ? " → " + String(installedCard.plugin.catalogueRevision).slice(0, 10) : "")
          : installedCard.update
            ? (Number(installedCard.update.behind || 0) > 0
                ? installedCard.update.behind + " incoming commit(s)" : "No incoming commits")
              + (Number(installedCard.update.ahead || 0) > 0
                ? "  ·  " + installedCard.update.ahead + " local" : "")
            : installedCard.plugin.id + (Array.isArray(installedCard.plugin.kinds)
                && installedCard.plugin.kinds.length > 0
                ? "  ·  " + installedCard.plugin.kinds.join(", ") : "")
        textFormat: Text.PlainText
        color: root.textMuted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        visible: Boolean(installedCard.plugin.managementError)
          || Boolean(installedCard.update && installedCard.update.error)
        width: parent.width
        text: installedCard.plugin.managementError
          || (installedCard.update ? installedCard.update.error : "") || ""
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
    }
  }

  component ProjectCard: Rectangle {
    id: card
    required property var project
    property bool expanded: false
    readonly property bool hasTrustedFeatures: Number(project.checks || 0)
      + Number(project.workflows || 0) + Number(project.environmentRequirements || 0) > 0
    readonly property string nextAction: Number(project.activeTestSessions || 0) > 0
      ? "test-session-stop"
      : project.deployment === "not-deployed" ? "link"
      : hasTrustedFeatures && !project.projectChecksTrusted ? "trust"
      : "test-session-start"
    readonly property string nextLabel: nextAction === "test-session-stop" ? "Stop test window"
      : nextAction === "link" ? "Start live development"
      : nextAction === "trust" ? "Review & trust commands"
      : "Open test window"
    implicitHeight: cardContent.implicitHeight + Style.space(20)
    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.055)
    radius: Style.cornerRadius
    border.color: project.deployment === "drifted"
      ? Color.urgent : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
    border.width: 1

    Column {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(10)
      spacing: Style.space(7)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Column {
          width: parent.width - stateText.width - Style.space(8)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: card.project.name || card.project.id
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: Number(card.project.workflows || 0) + " workflows  ·  "
              + Number(card.project.activeSessions || 0) + " active sessions"
              + (Number(card.project.activeTestSessions || 0) > 0
                ? "  ·  NESTED TEST RUNNING" : "")
              + (card.project.definitionChangedSinceTrust ? "  ·  TRUST STALE" : "")
            color: card.project.definitionChangedSinceTrust ? Color.urgent
              : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.48)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: card.project.id + "  ·  "
              + (card.project.revision ? String(card.project.revision).slice(0, 10) : "no git revision")
              + (card.project.dirty ? "  ·  DIRTY" : "")
              + "  ·  SECURITY " + String(card.project.securityReviewStatus || "incomplete").toUpperCase()
            textFormat: Text.PlainText
            color: card.project.dirty ? Color.urgent
              : card.project.securityReviewStatus === "ready" ? Color.accent
              : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          id: stateText
          text: String(card.project.deployment || "unknown").toUpperCase()
          color: card.project.deployment === "snapshot" ? Color.accent : root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(5)
        WorkbenchButton {
          label: card.nextLabel
          onTriggered: root.runAction(card.nextAction, card.project.id)
        }
        WorkbenchButton {
          label: card.expanded ? "Fewer actions" : "More actions"
          onTriggered: card.expanded = !card.expanded
        }
        WorkbenchButton {
          visible: card.expanded
          label: "Validate"
          onTriggered: root.runAction("validate", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.hasTrustedFeatures
          label: card.project.projectChecksTrusted ? "Untrust" : "Trust commands"
          onTriggered: root.runAction(card.project.projectChecksTrusted ? "untrust" : "trust", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded
          label: "Test"
          onTriggered: root.runAction("check", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded
          label: Number(card.project.activeTestSessions || 0) > 0 ? "Stop test window" : "Test window"
          onTriggered: root.runAction(
            Number(card.project.activeTestSessions || 0) > 0
              ? "test-session-stop" : "test-session-start",
            card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded
          label: "Diagnose"
          onTriggered: root.runAction("diagnose", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded
          label: card.project.securityReviewStatus === "stale" ? "Refresh audit brief" : "Security brief"
          onTriggered: root.runAction("security-review-prepare", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded
          label: "Security status"
          onTriggered: root.runAction("security-review-status", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && Number(card.project.securityReviewFindings || 0) > 0
          label: "Findings (" + Number(card.project.securityReviewFindings || 0) + ")"
          onTriggered: root.runAction("security-review-show", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.project.securityReviewStatus !== "incomplete"
          label: "Review history"
          onTriggered: root.runAction("security-review-history", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.project.securityReviewStatus === "needs-fixes"
            && Number(card.project.securityReviewFindings || 0) > 0
          label: "Start fix session"
          onTriggered: root.runAction("security-remediation-start", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.project.securityReviewStatus === "ready"
          label: "Security dossier"
          onTriggered: root.runAction("security-review-dossier", card.project.id)
        }
        WorkbenchButton { visible: card.expanded; label: "Release check"; onTriggered: root.runAction("release-check", card.project.id) }
        WorkbenchButton { visible: card.expanded; label: "Live link"; onTriggered: root.runAction("link", card.project.id) }
        WorkbenchButton { visible: card.expanded; label: "Snapshot"; onTriggered: root.runAction("snapshot", card.project.id) }
        WorkbenchButton { visible: card.expanded; label: "Rollback"; onTriggered: root.runAction("rollback", card.project.id) }
        WorkbenchButton {
          visible: card.expanded
          label: card.project.enabled === true ? "Disable" : "Enable"
          onTriggered: root.runAction(card.project.enabled === true ? "disable" : "enable", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.project.deployment !== "not-deployed"
          label: "Undeploy"
          onTriggered: root.runAction("undeploy", card.project.id)
        }
        WorkbenchButton {
          visible: card.expanded && card.project.deployment === "not-deployed"
            && Number(card.project.activeTestSessions || 0) === 0
          label: "Forget"
          onTriggered: root.runAction("remove", card.project.id)
        }
      }
    }
  }

  component UpdateCard: Rectangle {
    id: updateCard
    required property var entry
    readonly property bool marketplaceManaged: entry.kind === "marketplace"
    readonly property var update: entry.update || ({})
    readonly property var plugin: entry.plugin || ({})
    readonly property bool actionable: marketplaceManaged ? plugin.updateAvailable : update.updateable
    readonly property string displayId: marketplaceManaged ? String(plugin.id || "") : String(update.id || "")
    implicitHeight: updateCardContent.implicitHeight + Style.space(16)
    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.055)
    radius: Style.cornerRadius
    border.color: updateCard.actionable
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.45)
      : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.42)
    border.width: 1

    Column {
      id: updateCardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(8)
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(8)
        Column {
          width: parent.width - updateButton.width - Style.space(8)
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: updateCard.marketplaceManaged
              ? String(updateCard.plugin.name || updateCard.plugin.id || "")
              : updateCard.displayId
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: updateCard.marketplaceManaged
              ? "REVIEWED CATALOGUE UPDATE"
              : String(updateCard.update.state || "unknown").replace(/-/g, " ").toUpperCase()
                + (Number(updateCard.update.behind || 0) > 0 ? " · " + updateCard.update.behind + " incoming" : "")
                + (Number(updateCard.update.ahead || 0) > 0 ? " · " + updateCard.update.ahead + " local" : "")
            color: updateCard.actionable ? Color.accent : Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }
        WorkbenchButton {
          id: updateButton
          visible: updateCard.actionable
          label: "Update"
          enabled: !root.busy
          onTriggered: {
            if (updateCard.marketplaceManaged) root.updateManagedPlugin(updateCard.plugin)
            else root.applyUpdate(updateCard.update.id, updateCard.update.remoteRevision)
          }
        }
      }

      Text {
        visible: updateCard.marketplaceManaged
          ? Boolean(updateCard.plugin.installedRevision && updateCard.plugin.catalogueRevision)
          : Boolean(updateCard.update.currentRevision && updateCard.update.remoteRevision)
        width: parent.width
        text: updateCard.marketplaceManaged
          ? String(updateCard.plugin.installedRevision || "").slice(0, 10)
            + " → " + String(updateCard.plugin.catalogueRevision || "").slice(0, 10)
          : String(updateCard.update.currentRevision || "").slice(0, 10)
            + " → " + String(updateCard.update.remoteRevision || "").slice(0, 10)
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: !updateCard.marketplaceManaged
          && updateCard.update.commits && updateCard.update.commits.length > 0
        width: parent.width
        text: root.incomingSummary(updateCard.update.commits)
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
      }

      Text {
        visible: !updateCard.marketplaceManaged && Boolean(updateCard.update.diffStat)
        width: parent.width
        text: updateCard.update.diffStat || ""
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.62)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        maximumLineCount: 6
        elide: Text.ElideRight
      }

      Text {
        visible: !updateCard.marketplaceManaged && Boolean(updateCard.update.error)
        width: parent.width
        text: updateCard.update.error || ""
        color: Color.urgent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
      }
    }
  }

  component MarketplaceCard: Rectangle {
    id: marketplaceCard
    required property var plugin
    implicitHeight: marketplaceCardContent.implicitHeight + Style.space(18)
    color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.055)
    radius: Style.cornerRadius
    border.color: plugin.installed
      ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.42)
      : Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.12)
    border.width: 1

    Column {
      id: marketplaceCardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.space(9)
      spacing: Style.space(5)

      Row {
        width: parent.width
        spacing: Style.space(8)
        Column {
          width: parent.width - marketplaceActions.width - Style.space(8)
          spacing: Style.space(2)
          Text {
            width: parent.width
            text: marketplaceCard.plugin.name + "  ·  " + marketplaceCard.plugin.version
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: marketplaceCard.plugin.kind + "  ·  " + marketplaceCard.plugin.category
              + "  ·  " + marketplaceCard.plugin.author
            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.58)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
        Row {
          id: marketplaceActions
          spacing: Style.space(5)
          WorkbenchButton {
            visible: marketplaceCard.plugin.installable
            label: "Install & enable"
            enabled: !root.busy
            onTriggered: root.installMarketplace(marketplaceCard.plugin)
          }
          WorkbenchButton {
            visible: marketplaceCard.plugin.managed && marketplaceCard.plugin.updateAvailable
            label: "Update"
            enabled: !root.busy
            onTriggered: root.updateMarketplace(marketplaceCard.plugin)
          }
          WorkbenchButton {
            visible: marketplaceCard.plugin.managed
            label: root.marketplaceConfirmation === "repair:" + marketplaceCard.plugin.id
              ? "Confirm repair" : "Repair"
            enabled: !root.busy
            onTriggered: root.confirmedMarketplaceAction("repair", marketplaceCard.plugin)
          }
          WorkbenchButton {
            visible: marketplaceCard.plugin.managed
            label: root.marketplaceConfirmation === "uninstall:" + marketplaceCard.plugin.id
              ? "Confirm uninstall" : "Uninstall"
            enabled: !root.busy
            onTriggered: root.confirmedMarketplaceAction("uninstall", marketplaceCard.plugin)
          }
        }
      }

      Text {
        width: parent.width
        text: marketplaceCard.plugin.description
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: marketplaceCard.plugin.id
          + (marketplaceCard.plugin.tags.length ? "  ·  " + marketplaceCard.plugin.tags.join(", ") : "")
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.52)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: marketplaceCard.plugin.builtIn ? "BUILT IN"
          : marketplaceCard.plugin.managed
            ? "WORKBENCH MANAGED"
              + (marketplaceCard.plugin.updateAvailable ? "  ·  UPDATE AVAILABLE" : "")
          : marketplaceCard.plugin.installed ? "INSTALLED"
          : String(marketplaceCard.plugin.verificationStatus || "unverified").toUpperCase()
            + (marketplaceCard.plugin.reviewedRevision
              ? "  ·  REVIEWED " + String(marketplaceCard.plugin.reviewedRevision).slice(0, 10)
              : "")
        color: marketplaceCard.plugin.installed || marketplaceCard.plugin.verificationStatus === "verified"
          ? Color.accent : Color.urgent
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      Text {
        width: parent.width
        text: marketplaceCard.plugin.repo
        color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.46)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
      }
    }
  }
}
