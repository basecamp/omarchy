set(OMARCHY_PLUGIN_PRESENTATION_DIR
  "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginPresentation")
install(FILES
  qml/qmldir qml/Color.qml qml/Style.qml qml/Panel.qml
  qml/BarIconButton.qml qml/KeyboardPanel.qml qml/PanelKeyCatcher.qml
  qml/PanelHero.qml qml/PanelSectionHeader.qml qml/PanelSeparator.qml
  qml/PanelSlider.qml qml/ToggleSwitch.qml
  qml/CursorSurface.qml
  DESTINATION "${OMARCHY_PLUGIN_PRESENTATION_DIR}")

if(BUILD_TESTING)
  add_test(NAME plugin-presentation-authority-boundary
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/presentation_boundary_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/qml")
  set_tests_properties(plugin-presentation-authority-boundary PROPERTIES
    TIMEOUT 5 LABELS "qml;presentation;security;api-snapshot")
endif()
