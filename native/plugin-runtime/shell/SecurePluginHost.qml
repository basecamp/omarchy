pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Omarchy.PluginHost 1.0
import "SecureSurfacePolicy.js" as SurfacePolicy

Item {
  id: root

  property var shell: null
  property var barWidgetRegistry: null
  readonly property int maximumPermissionChoiceBytes: 262176
  readonly property int maximumPermissionChoiceChunkBytes: 90000
  readonly property int maximumArchivePathBytes: 4096
  property var barEntries: []
  property string barOwnerScreenName: ""
  readonly property string liveScreenSignature: liveScreenNames().join("\n")
  readonly property string focusedScreenName: {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  visible: false

  Component.onCompleted: {
    if (root.shell) PluginManager.configureSettingsHost(root.shell)
  }
  onShellChanged: {
    if (root.shell) PluginManager.configureSettingsHost(root.shell)
  }

  // Same-UID session IPC is trusted host control and is intentionally outside
  // the isolated v2 worker boundary. It receives only plugin ids, opaque
  // operation/row ids, and bounded choice JSON; the manager retains exact
  // revision and authority context.
  IpcHandler {
    target: "plugin-permissions"

    function list(pluginId: string): string {
      return PluginManager.permissions.beginList(pluginId)
    }

    function review(pluginId: string): string {
      return PluginManager.permissions.beginInteractiveCliReview(pluginId)
    }

    function apply(reviewOperationId: string, chunk0: string, chunk1: string, chunk2: string): string {
      if (chunk0.length > root.maximumPermissionChoiceChunkBytes
          || chunk1.length > root.maximumPermissionChoiceChunkBytes
          || chunk2.length > root.maximumPermissionChoiceChunkBytes)
        return ""
      var choicesJson = chunk0 + chunk1 + chunk2
      if (choicesJson.length > root.maximumPermissionChoiceBytes) return ""
      return PluginManager.permissions.applyInteractiveCli(reviewOperationId, choicesJson)
    }

    function revoke(sourceOperationId: string, rowId: string): string {
      return PluginManager.permissions.revoke(sourceOperationId, rowId)
    }

    function poll(operationId: string): string {
      return PluginManager.permissions.poll(operationId)
    }
  }

  IpcHandler {
    target: "plugin-security"

    function installArchive(archivePath: string): string {
      if (archivePath.length === 0
          || archivePath.length > root.maximumArchivePathBytes)
        return ""
      return PluginManager.installer.begin(archivePath)
    }

    function pollInstall(operationId: string): string {
      if (operationId.length !== 40) return ""
      return PluginManager.installer.poll(operationId)
    }

    function reviewInstall(operationId: string): string {
      if (operationId.length !== 40) return ""
      return PluginManager.installer.beginReview(operationId)
    }
  }

  function liveScreenNames() {
    var names = []
    for (var index = 0; index < Quickshell.screens.length; index++)
      names.push(String(Quickshell.screens[index].name || ""))
    return SurfacePolicy.liveScreenNames(names)
  }

  function screenForOpen() {
    var focusedName = SurfacePolicy.chooseOpenScreen(liveScreenNames(), focusedScreenName)
    for (var index = 0; index < Quickshell.screens.length; index++)
      if (Quickshell.screens[index].name === focusedName) return Quickshell.screens[index]
    return null
  }

  function refreshBarOwner() {
    barOwnerScreenName = SurfacePolicy.chooseOwner(
      liveScreenNames(), focusedScreenName, barOwnerScreenName, barEntries.length > 0)
  }

  function refreshBarEntries() {
    var next = []
    for (var index = 0; index < barEntryInstances.count; index++) {
      var entry = barEntryInstances.objectAt(index)
      if (entry) next.push({ id: entry.surfaceKey, section: entry.defaultSection })
    }
    barEntries = next
    refreshBarOwner()
  }

  onLiveScreenSignatureChanged: refreshBarOwner()
  onFocusedScreenNameChanged: refreshBarOwner()

  Instantiator {
    id: barEntryInstances
    model: PluginManager.barSurfaces

    onObjectAdded: Qt.callLater(root.refreshBarEntries)
    onObjectRemoved: Qt.callLater(root.refreshBarEntries)

    delegate: QtObject {
      id: barEntry

      required property string surfaceKey
      required property string pluginId
      required property string surfaceName
      required property string generation
      required property string publicationRevision
      required property int maximumWidth
      required property int maximumHeight
      required property string defaultSection
      property var registeredRegistry: null

      property Component surfaceComponent: Component {
        SecureBarSurface {
          surfaceService: PluginManager
          surfaceKey: barEntry.surfaceKey
          generation: barEntry.generation
          maximumWidth: barEntry.maximumWidth
          maximumHeight: barEntry.maximumHeight
        }
      }

      function unregisterSurface() {
        if (!registeredRegistry) return
        var metadata = registeredRegistry.metadataFor(surfaceKey)
        if (metadata && metadata.generation === generation
            && metadata.publicationRevision === publicationRevision)
          registeredRegistry.unregister(surfaceKey)
        registeredRegistry = null
      }

      function syncRegistration() {
        if (registeredRegistry === root.barWidgetRegistry) return
        unregisterSurface()
        if (!root.barWidgetRegistry) return
        root.barWidgetRegistry.register(surfaceKey, surfaceComponent, {
          security: "sandboxed-v2",
          pluginId: pluginId,
          surfaceName: surfaceName,
          generation: generation,
          publicationRevision: publicationRevision,
          defaultSection: defaultSection
        })
        registeredRegistry = root.barWidgetRegistry
      }

      Component.onCompleted: syncRegistration()
      Component.onDestruction: unregisterSurface()
    }
  }

  onBarWidgetRegistryChanged: {
    for (var index = 0; index < barEntryInstances.count; index++) {
      var entry = barEntryInstances.objectAt(index)
      if (entry) entry.syncRegistration()
    }
  }

  Instantiator {
    model: PluginManager.panelSurfaces
    delegate: QtObject {
      id: panelEntry

      required property string surfaceKey
      required property string generation
      required property bool initiallyVisible
      required property int maximumWidth
      required property int maximumHeight
      required property bool dynamicInputRegions

      property SecurePanelSurface surface: SecurePanelSurface {
        host: root
        surfaceService: PluginManager
        surfaceKey: panelEntry.surfaceKey
        generation: panelEntry.generation
        initiallyVisible: panelEntry.initiallyVisible
        maximumWidth: panelEntry.maximumWidth
        maximumHeight: panelEntry.maximumHeight
        dynamicInputRegions: panelEntry.dynamicInputRegions
      }
    }
  }

  Instantiator {
    model: PluginManager.overlaySurfaces
    delegate: QtObject {
      id: overlayEntry

      required property string surfaceKey
      required property string generation
      required property bool initiallyVisible
      required property int maximumWidth
      required property int maximumHeight
      required property bool dynamicInputRegions

      property SecureOverlaySurface surface: SecureOverlaySurface {
        host: root
        surfaceService: PluginManager
        surfaceKey: overlayEntry.surfaceKey
        generation: overlayEntry.generation
        initiallyVisible: overlayEntry.initiallyVisible
        maximumWidth: overlayEntry.maximumWidth
        maximumHeight: overlayEntry.maximumHeight
        dynamicInputRegions: overlayEntry.dynamicInputRegions
      }
    }
  }
}
