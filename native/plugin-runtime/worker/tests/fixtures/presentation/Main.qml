import QtQuick
import Omarchy.PluginPresentation 1.0

Item {
  objectName: "presentation-loaded"
  width: 320
  height: 240

  BorderSurface {}
  BarWidget {}
  BrokerProcess {}
  Button {}
  PackagedText { preload: false }
  PanelSlider {}
  PrivateStorage {}
  StdioCollector {}
  TextField {}
  ToolTip {}
  WidgetButton {}
}
