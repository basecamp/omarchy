import QtQuick
import qs.Ui
import "BarModel.js" as BarModel

// A collapsible group of bar widgets. Kept in its own file rather than an inline
// component of Bar.qml on purpose: a group contains widget slots, and a widget
// slot may itself be a group, so an inline component would make Bar.qml's
// components form a resolution cycle — which QML forbids ("Inline components
// form a cycle!"). A file type can be referenced recursively, so the recursion
// lives here.
//
// The children are rendered by a ModuleList handed in as `listComponent` (a
// runtime Component created by Bar.qml), so this file never names the bar's
// inline ModuleList / ModuleSlot types and the cycle stays broken.
Item {
  id: root

  property var bar: null
  property var entry: null
  property string region: ""
  // A bare ModuleList component supplied by the bar; its entries/region are
  // filled once it loads.
  property Component listComponent: null

  readonly property var groupSettings: BarModel.entrySettings(entry)

  implicitWidth: collapsible.implicitWidth
  implicitHeight: collapsible.implicitHeight

  BarCollapsible {
    id: collapsible
    anchors.fill: parent
    bar: root.bar
    collapsedByDefault: root.groupSettings.collapsed !== false
    expandOnHover: root.groupSettings.expandOnHover !== false
    // A distinct default glyph so a group next to the tray drawer does not read
    // as a second tray; an entry may override it via "icon".
    icon: root.groupSettings.icon !== undefined && root.groupSettings.icon !== null
      ? String(root.groupSettings.icon) : "\uf141"

    contentComponent: Component {
      Loader {
        sourceComponent: root.listComponent
        onLoaded: {
          if (!item) return
          item.entries = BarModel.groupItems(root.entry)
          item.region = root.region
          item.draggable = false
        }
      }
    }
  }
}
