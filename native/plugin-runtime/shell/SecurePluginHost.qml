pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Omarchy.PluginHost 1.0

Item {
  id: root

  property var shell: null
  property var barWidgetRegistry: null

  visible: false

  function screenFor(name) {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return null
  }

  PluginSurfaceService { id: surfaceService }

  Instantiator {
    id: barEntries
    model: surfaceService.barSurfaces

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
          surfaceService: surfaceService
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
    model: surfaceService.panelSurfaces
    delegate: Component {
      SecurePanelSurface {
        required property string surfaceKey
        required property string generation
        required property string screenName
        required property bool initiallyVisible
        required property int maximumWidth

        host: root
        surfaceService: surfaceService
      }
    }
  }

  Variants {
    model: surfaceService.overlaySurfaces
    delegate: Component {
      SecureOverlaySurface {
        required property string surfaceKey
        required property string generation
        required property string screenName
        required property bool initiallyVisible
        required property int maximumWidth
        required property int maximumHeight

        host: root
        surfaceService: surfaceService
      }
    }
  }
}
