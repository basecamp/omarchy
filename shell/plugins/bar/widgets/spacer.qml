import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "spacer"


  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int span: settings && settings.size !== undefined ? Number(settings.size) : 12

  implicitWidth: vertical ? (bar ? bar.barSize : 28) : span
  implicitHeight: vertical ? span : (bar ? bar.barSize : 26)
  visible: span > 0
}
