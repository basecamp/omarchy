set(plugin_host_module_dir "${QT_QML_OUTPUT_DIRECTORY}/Omarchy/PluginHost")

qt_add_qml_module(omarchy-plugin-host-bridge
  SHARED
  URI Omarchy.PluginHost
  VERSION 1.0
  PLUGIN_TARGET omarchy-plugin-host-bridge
  OUTPUT_DIRECTORY "${plugin_host_module_dir}"
  SOURCES
    src/PluginManager.cpp
    src/PluginManager.h
    src/ProductionSurfaceEndpoint.cpp
    src/ProductionSurfaceEndpoint.h
    src/ProductionSurfaceEndpointOwner.cpp
    src/ProductionSurfaceEndpointOwner.h
    src/PluginSurfaceService.cpp
    src/PluginSurfaceService.h
    ../trusted-bridge/src/remote_surface.hpp
)

omarchy_plugin_target_defaults(omarchy-plugin-host-bridge)
target_include_directories(omarchy-plugin-host-bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge/src"
)
target_link_libraries(omarchy-plugin-host-bridge PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  Omarchy::PluginRuntimeVersion
  omarchy-plugin-trusted-bridge
  omarchy-plugin-host-session
  omarchy-plugin-authenticated-session
  omarchy-plugin-surface-host
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
    src/PluginManager.cpp
    tests/PluginManager_test.cpp
    src/ProductionSurfaceEndpoint.cpp
    tests/ProductionSurfaceEndpoint_test.cpp
    src/ProductionSurfaceEndpointOwner.cpp
    tests/ProductionSurfaceEndpointOwner_test.cpp
    src/PluginSurfaceService.cpp
    tests/PluginSurfaceService_test.cpp
    ../channel-integration/src/production_plugin_bootstrap.cpp
    ../channel-integration/src/production_plugin_roots.cpp
  )
  omarchy_plugin_target_defaults(omarchy-plugin-surface-service-test)
  target_compile_definitions(omarchy-plugin-surface-service-test PRIVATE
    OMARCHY_PLUGIN_MANAGER_TESTING
    OMARCHY_PRODUCTION_PLUGIN_BOOTSTRAP_TESTING
    OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING
    OMARCHY_PRODUCTION_SURFACE_ENDPOINT_OWNER_TESTING)
  target_include_directories(omarchy-plugin-surface-service-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration/src"
  )
  target_link_libraries(omarchy-plugin-surface-service-test PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
    omarchy-plugin-trusted-bridge
    omarchy-plugin-host-session
    omarchy-plugin-authenticated-session
    omarchy-plugin-surface-host
  )
  add_test(NAME plugin-surface-service
    COMMAND omarchy-plugin-surface-service-test)
  set_tests_properties(plugin-surface-service PROPERTIES
    TIMEOUT 10
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME="
    LABELS "unit;shell;bridge;security")
endif()
