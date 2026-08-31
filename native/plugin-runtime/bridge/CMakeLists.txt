set(plugin_host_module_dir "${QT_QML_OUTPUT_DIRECTORY}/Omarchy/PluginHost")

qt_add_qml_module(omarchy-plugin-host-bridge
  SHARED
  URI Omarchy.PluginHost
  VERSION 1.0
  PLUGIN_TARGET omarchy-plugin-host-bridge
  OUTPUT_DIRECTORY "${plugin_host_module_dir}"
  SOURCES
    src/PermissionControl.cpp
    src/PermissionControl.h
    src/PluginManager.cpp
    src/PluginManager.h
    src/SurfaceEndpoint.cpp
    src/SurfaceEndpoint.h
    src/SurfaceEndpointOwner.cpp
    src/SurfaceEndpointOwner.h
    src/SurfaceProjectionModel.cpp
    src/SurfaceProjectionModel.h
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
    src/PermissionControl.cpp
    src/PluginManager.cpp
    tests/PluginManager_test.cpp
    src/SurfaceEndpoint.cpp
    tests/SurfaceEndpoint_test.cpp
    src/SurfaceEndpointOwner.cpp
    tests/SurfaceEndpointOwner_test.cpp
    src/SurfaceProjectionModel.cpp
    tests/SurfaceProjectionModel_test.cpp
    ../channel-integration/src/runtime_bootstrap.cpp
    ../channel-integration/src/runtime_roots.cpp
  )
  omarchy_plugin_target_defaults(omarchy-plugin-surface-service-test)
  target_compile_definitions(omarchy-plugin-surface-service-test PRIVATE
    OMARCHY_PLUGIN_MANAGER_TESTING
    OMARCHY_RUNTIME_BOOTSTRAP_TESTING
    OMARCHY_RUNTIME_ROOTS_TESTING
    OMARCHY_SURFACE_ENDPOINT_TESTING
    OMARCHY_SURFACE_ENDPOINT_OWNER_TESTING)
  target_include_directories(omarchy-plugin-surface-service-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration/tests"
  )
  target_link_libraries(omarchy-plugin-surface-service-test PRIVATE
    Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml Qt6::Quick
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
