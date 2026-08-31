pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Omarchy.PluginHost 1.0

Item {
  id: root

  property var shell: null
  property var barWidgetRegistry: null
  readonly property int maximumPermissionChoiceBytes: 262176
  readonly property int maximumPermissionChoiceChunkBytes: 90000

  visible: false

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

  function screenFor(name) {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return null
  }

  Instantiator {
    id: barEntries
    model: PluginManager.barSurfaces

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
    for (var index = 0; index < barEntries.count; index++) {
      var entry = barEntries.objectAt(index)
      if (entry) entry.syncRegistration()
    }
  }

  Variants {
    model: PluginManager.panelSurfaces
    delegate: Component {
      SecurePanelSurface {
        required property string surfaceKey
        required property string generation
        required property string screenName
        required property bool initiallyVisible
        required property int maximumWidth
        required property int maximumHeight
        required property bool dynamicInputRegions

        host: root
        surfaceService: PluginManager
      }
    }
  }

  Variants {
    model: PluginManager.overlaySurfaces
    delegate: Component {
      SecureOverlaySurface {
        required property string surfaceKey
        required property string generation
        required property string screenName
        required property bool initiallyVisible
        required property int maximumWidth
        required property int maximumHeight
        required property bool dynamicInputRegions

        host: root
        surfaceService: PluginManager
      }
    }
  }
}
