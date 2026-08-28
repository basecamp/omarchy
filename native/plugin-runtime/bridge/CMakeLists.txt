set(plugin_host_module_dir "${QT_QML_OUTPUT_DIRECTORY}/Omarchy/PluginHost")

qt_add_qml_module(omarchy-plugin-host-bridge
  SHARED
  URI Omarchy.PluginHost
  VERSION 1.0
  PLUGIN_TARGET omarchy-plugin-host-bridge
  OUTPUT_DIRECTORY "${plugin_host_module_dir}"
  SOURCES PluginHostInfo.cpp PluginHostInfo.h
)

omarchy_plugin_target_defaults(omarchy-plugin-host-bridge)
target_link_libraries(omarchy-plugin-host-bridge PRIVATE Qt6::Core Qt6::Qml Omarchy::PluginRuntimeVersion)

install(TARGETS omarchy-plugin-host-bridge LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginHost")
install(FILES
  "${plugin_host_module_dir}/qmldir"
  "${plugin_host_module_dir}/omarchy-plugin-host-bridge.qmltypes"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginHost"
)
