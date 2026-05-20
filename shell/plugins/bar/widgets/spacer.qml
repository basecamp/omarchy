import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "spacer"

  readonly property int span: settings && settings.size !== undefined ? Number(settings.size) : 12

  implicitWidth: vertical ? barSize : span
  implicitHeight: vertical ? span : barSize
  visible: span > 0
}
