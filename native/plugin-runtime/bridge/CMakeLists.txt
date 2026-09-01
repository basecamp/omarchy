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
    src/PluginInstallControl.cpp
    src/PluginInstallControl.h
    src/PluginManager.cpp
    src/PluginManager.h
    src/PluginRuntimeCatalog.cpp
    src/PluginRuntimeController.cpp
    src/PluginRuntimeController.h
    src/PluginRuntimePermissions.cpp
    src/PluginRuntimeSurfaces.cpp
    src/SurfaceEndpoint.cpp
    src/SurfaceEndpoint.h
    src/SurfaceEndpointOwner.cpp
    src/SurfaceEndpointOwner.h
    src/SurfaceProjectionModel.cpp
    src/SurfaceProjectionModel.h
    src/runtime_contract.cpp
    ../trusted-bridge/src/remote_surface.hpp
)

omarchy_plugin_target_defaults(omarchy-plugin-host-bridge)
set_target_properties(omarchy-plugin-host-bridge PROPERTIES
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN YES)
target_link_options(omarchy-plugin-host-bridge PRIVATE
  "LINKER:--exclude-libs,ALL")
target_include_directories(omarchy-plugin-host-bridge PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge/src"
)
target_link_libraries(omarchy-plugin-host-bridge PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  Omarchy::PluginRuntimeVersion
  Omarchy::PluginRuntimePaths
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
    src/PluginInstallControl.cpp
    src/PluginManager.cpp
    src/PluginRuntimeCatalog.cpp
    src/PluginRuntimeController.cpp
    src/PluginRuntimePermissions.cpp
    src/PluginRuntimeSurfaces.cpp
    tests/PluginManager_test.cpp
    tests/PluginManagerTestAccess.cpp
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
    OMARCHY_NEUTRAL_SURFACE_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures/neutral-surfaces"
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
  add_executable(omarchy-plugin-permission-control-contract-test
    src/PermissionControl.cpp
    src/PluginInstallControl.cpp
    src/PluginManager.cpp
    src/PluginRuntimeCatalog.cpp
    src/PluginRuntimeController.cpp
    src/PluginRuntimePermissions.cpp
    src/PluginRuntimeSurfaces.cpp
    tests/PermissionControl_contract_test.cpp
    tests/PluginManagerTestAccess.cpp
    src/SurfaceEndpoint.cpp
    src/SurfaceEndpointOwner.cpp
    src/SurfaceProjectionModel.cpp
    ../channel-integration/src/runtime_bootstrap.cpp
    ../channel-integration/src/runtime_roots.cpp
    ../channel-integration/src/session_runtime_factory.cpp
  )
  omarchy_plugin_target_defaults(omarchy-plugin-permission-control-contract-test)
  target_compile_definitions(omarchy-plugin-permission-control-contract-test PRIVATE
    OMARCHY_PLUGIN_MANAGER_TESTING
    OMARCHY_PLUGIN_SESSION_TESTING
    OMARCHY_RUNTIME_BOOTSTRAP_TESTING
    OMARCHY_RUNTIME_ROOTS_TESTING
    OMARCHY_SURFACE_ENDPOINT_OWNER_TESTING)
  target_include_directories(omarchy-plugin-permission-control-contract-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration/src"
    "${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration/tests"
    "${CMAKE_CURRENT_SOURCE_DIR}/../host-session/tests"
  )
  target_link_libraries(omarchy-plugin-permission-control-contract-test PRIVATE
    Qt6::Core Qt6::DBus Qt6::Gui Qt6::Qml Qt6::Quick
    omarchy-plugin-trusted-bridge
    omarchy-plugin-host-session
    omarchy-plugin-authenticated-session
    omarchy-plugin-surface-host
  )
  add_test(NAME plugin-permission-control-contract
    COMMAND omarchy-plugin-permission-control-contract-test)
  set_tests_properties(plugin-permission-control-contract PROPERTIES
    TIMEOUT 10
    SKIP_RETURN_CODE 77
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME="
    LABELS "unit;shell;bridge;security;permission-contract")

  add_test(NAME plugin-public-permission-lifecycle
    COMMAND omarchy-plugin-surface-service-test
            --public-permission-lifecycle-only)
  set_tests_properties(plugin-public-permission-lifecycle PROPERTIES
    TIMEOUT 30
    SKIP_RETURN_CODE 77
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME="
    LABELS "integration;shell;bridge;security;permissions;lifecycle")

  add_test(NAME plugin-neutral-surfaces-real-bwrap
    COMMAND omarchy-plugin-surface-service-test
            --neutral-surfaces-real-bwrap-only)
  set_tests_properties(plugin-neutral-surfaces-real-bwrap PROPERTIES
    TIMEOUT 30
    SKIP_RETURN_CODE 77
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software"
    LABELS "integration;shell;bridge;security;sandbox;real-bwrap;fixtures")
endif()
