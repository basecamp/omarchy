import QtQuick

// A worker render-scene root. Host windows and compositor surfaces are not
// represented here; schema-v2 surface declarations retain that authority.
Item {
  property string reloadableId: ""
}
