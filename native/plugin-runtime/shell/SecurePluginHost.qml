pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Omarchy.PluginHost 1.0

Item {
  id: root

  property var shell: null
  property var barWidgetRegistry: null
  property var registeredBarIds: []

  readonly property var declarations: surfaceService.surfaces
  readonly property var barEntries: {
    var revision = surfaceService.revision
    var result = []
    for (var i = 0; i < declarations.length; i++) {
      var declaration = declarations[i]
      if (declaration.role === "bar")
        result.push({ id: declaration.surfaceKey, section: declaration.defaultSection })
    }
    return result
  }
  readonly property var panelDeclarations: filteredDeclarations("panel")
  readonly property var overlayDeclarations: filteredDeclarations("overlay")

  visible: false

  function filteredDeclarations(role) {
    var revision = surfaceService.revision
    var result = []
    for (var i = 0; i < declarations.length; i++)
      if (declarations[i].role === role) result.push(declarations[i])
    return result
  }

  function declarationFor(surfaceKey) {
    var revision = surfaceService.revision
    for (var i = 0; i < declarations.length; i++)
      if (declarations[i].surfaceKey === surfaceKey) return declarations[i]
    return null
  }

  function screenFor(name) {
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    return null
  }

  function syncDeclarations() {
    if (!barWidgetRegistry) return
    for (var old = 0; old < registeredBarIds.length; old++)
      barWidgetRegistry.unregister(registeredBarIds[old])
    var nextIds = []
    for (var bar = 0; bar < declarations.length; bar++) {
      var entry = declarations[bar]
      if (entry.role !== "bar") continue
      barWidgetRegistry.register(entry.surfaceKey, barSurfaceComponent, {
        security: "sandboxed-v2",
        pluginId: entry.pluginId,
        surfaceName: entry.surfaceName
      })
      nextIds.push(entry.surfaceKey)
    }
    registeredBarIds = nextIds
  }

  PluginSurfaceService {
    id: surfaceService

    onSurfacesChanged: root.syncDeclarations()
  }

  Component {
    id: barSurfaceComponent
    SecureBarSurface { host: root; surfaceService: surfaceService }
  }

  Variants {
    model: root.panelDeclarations
    delegate: Component {
      SecurePanelSurface {
        required property var modelData
        host: root
        surfaceService: surfaceService
        declaration: modelData
      }
    }
  }

  Variants {
    model: root.overlayDeclarations
    delegate: Component {
      SecureOverlaySurface {
        required property var modelData
        host: root
        surfaceService: surfaceService
        declaration: modelData
      }
    }
  }

  Component.onDestruction: {
    if (!barWidgetRegistry) return
    for (var i = 0; i < registeredBarIds.length; i++)
      barWidgetRegistry.unregister(registeredBarIds[i])
  }
}
