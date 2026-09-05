pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// This Region projects only host-validated input regions. The plugin cannot
// instantiate it or choose dynamicInputRegions: both are owned by the trusted
// shell and populated from the admitted surface policy.
Region {
  id: root

  required property var surface
  required property bool dynamicInputRegions
  readonly property int maximumRegionCount: 16

  // Surface allocation is not yet owned by the product manager. Until it is,
  // refuse compositor input whenever the displayed item is translated to a
  // fractional coordinate or scaled away from its trusted logical allocation.
  readonly property bool oneToOneGeometry:
    surface !== null
    && surface.x === Math.trunc(surface.x)
    && surface.y === Math.trunc(surface.y)
    && surface.width > 0
    && surface.height > 0
    && surface.width === Math.trunc(surface.width)
    && surface.height === Math.trunc(surface.height)
    && surface.implicitWidth > 0
    && surface.implicitHeight > 0
    && surface.width === surface.implicitWidth
    && surface.height === surface.implicitHeight
  readonly property bool acceptedDynamicRegions:
    oneToOneGeometry
    && dynamicInputRegions
    && surface.inputRegions !== undefined
    && surface.inputRegions.length <= root.maximumRegionCount

  // Fixed-region policy is exactly the remote item. Dynamic policy starts
  // empty and becomes interactive only after HostInputRegionRouter accepts an
  // update and RemotePluginSurface publishes the accepted rectangles.
  item: oneToOneGeometry && !dynamicInputRegions ? surface : null

  component RegionSlot: Region {
    required property int slot
    readonly property bool populated:
      root.acceptedDynamicRegions && slot < root.surface.inputRegions.length
    readonly property var accepted: populated ? root.surface.inputRegions[slot] : null

    x: populated ? root.surface.x + accepted.x : 0
    y: populated ? root.surface.y + accepted.y : 0
    width: populated ? accepted.width : 0
    height: populated ? accepted.height : 0
  }

  RegionSlot { slot: 0 }
  RegionSlot { slot: 1 }
  RegionSlot { slot: 2 }
  RegionSlot { slot: 3 }
  RegionSlot { slot: 4 }
  RegionSlot { slot: 5 }
  RegionSlot { slot: 6 }
  RegionSlot { slot: 7 }
  RegionSlot { slot: 8 }
  RegionSlot { slot: 9 }
  RegionSlot { slot: 10 }
  RegionSlot { slot: 11 }
  RegionSlot { slot: 12 }
  RegionSlot { slot: 13 }
  RegionSlot { slot: 14 }
  RegionSlot { slot: 15 }
}
