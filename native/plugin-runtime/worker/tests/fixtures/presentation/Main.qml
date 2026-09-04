import QtQuick
import Omarchy.PluginPresentation 1.0

Item {
  objectName: String(Color.foreground) === "#123456"
    && Style.bar.statusSlot === 23 ? "presentation-themed" : "presentation-loaded"
  width: 320
  height: 240

  BorderSurface {}
  BarWidget {}
  BrokerProcess {}
  Button {}
  CursorSurface {}
  Dropdown {}
  KeyboardPanel {}
  PackagedText { preload: false }
  Panel {}
  PanelActionButton {}
  PanelHero {}
  PanelKeyCatcher {}
  PanelSectionHeader {}
  PanelSeparator {}
  PanelSlider {}
  PrivateStorage {}
  StdioCollector {}
  TextField {}
  ToolTip {}
  Toggle {}
  ToggleSwitch {}
  WidgetButton {}
}
