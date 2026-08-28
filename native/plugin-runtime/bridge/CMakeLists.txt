set(plugin_host_module_dir "${QT_QML_OUTPUT_DIRECTORY}/Omarchy/PluginHost")

qt_add_qml_module(omarchy-plugin-host-bridge
  SHARED
  URI Omarchy.PluginHost
  VERSION 1.0
  PLUGIN_TARGET omarchy-plugin-host-bridge
  OUTPUT_DIRECTORY "${plugin_host_module_dir}"
  SOURCES
    PluginHostInfo.cpp
    PluginHostInfo.h
    ../trusted-bridge/remote_surface.cpp
    ../trusted-bridge/remote_surface.hpp
    ../trusted-bridge/render_input_transport.cpp
    ../trusted-bridge/render_input_transport.hpp
)

omarchy_plugin_target_defaults(omarchy-plugin-host-bridge)
target_include_directories(omarchy-plugin-host-bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
)
target_link_libraries(omarchy-plugin-host-bridge PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  Omarchy::PluginRuntimeVersion
  omarchy-plugin-surface-contract
  omarchy-plugin-wire
)

install(TARGETS omarchy-plugin-host-bridge LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginHost")
install(FILES
  "${plugin_host_module_dir}/qmldir"
  "${plugin_host_module_dir}/omarchy-plugin-host-bridge.qmltypes"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginHost"
)
