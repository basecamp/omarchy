import QtQuick

// Scalar-only view of the active bar for plugins that position independent
// windows. The active Bar QObject is never retained here.
QtObject {
  required property string ownerPluginId

  property bool barHidden: false
  property int barSize: 0
  property string fontFamily: ""
  property string position: "top"
}
