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
    PluginSurfaceService.cpp
    PluginSurfaceService.h
    ../trusted-bridge/remote_surface.hpp
)

omarchy_plugin_target_defaults(omarchy-plugin-host-bridge)
target_include_directories(omarchy-plugin-host-bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
)
target_link_libraries(omarchy-plugin-host-bridge PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  Omarchy::PluginRuntimeVersion
  omarchy-plugin-trusted-bridge
  omarchy-plugin-host-session
  omarchy-plugin-surface-contract
  omarchy-plugin-wire
)

install(TARGETS omarchy-plugin-host-bridge LIBRARY DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/qml/Omarchy/PluginHost")
install(FILES
  "${plugin_host_module_dir}/qmldir"
  "${plugin_host_module_dir}/omarchy-plugin-host-bridge.qmltypes"
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/qml/Omarchy/PluginHost"
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-surface-service-test
    PluginSurfaceService.cpp
    PluginSurfaceService_test.cpp
  )
  omarchy_plugin_target_defaults(omarchy-plugin-surface-service-test)
  target_include_directories(omarchy-plugin-surface-service-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
  )
  target_link_libraries(omarchy-plugin-surface-service-test PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
    omarchy-plugin-trusted-bridge
    omarchy-plugin-host-session
  )
  add_test(NAME plugin-surface-service
    COMMAND omarchy-plugin-surface-service-test)
  set_tests_properties(plugin-surface-service PROPERTIES
    TIMEOUT 10
    LABELS "unit;shell;bridge;security")
endif()
