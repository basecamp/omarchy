qt_add_executable(omarchy-plugin-host main.cpp)

omarchy_plugin_target_defaults(omarchy-plugin-host)
target_link_libraries(omarchy-plugin-host PRIVATE
  Qt6::Core Qt6::Gui Qt6::Quick
  Omarchy::PluginRuntimeVersion
  omarchy-plugin-product-host
  omarchy-plugin-broker-runtime
  omarchy-plugin-providers
  omarchy-plugin-lifecycle
  omarchy-plugin-audit-store)

install(TARGETS omarchy-plugin-host RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")

if(BUILD_TESTING)
  qt_add_executable(omarchy-plugin-product-e2e-host main.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-product-e2e-host)
  target_compile_definitions(omarchy-plugin-product-e2e-host PRIVATE
    OMARCHY_PLUGIN_PRODUCT_E2E=1)
  target_link_libraries(omarchy-plugin-product-e2e-host PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick
    Omarchy::PluginRuntimeVersion
    omarchy-plugin-product-host
    omarchy-plugin-broker-runtime
    omarchy-plugin-providers
    omarchy-plugin-lifecycle
    omarchy-plugin-audit-store)
  add_dependencies(omarchy-plugin-product-e2e-host
    omarchy-plugin-qml-worker omarchy-plugin-permission-store)
  add_test(NAME plugin-product-e2e-bwrap
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/product_e2e_test.sh"
      $<TARGET_FILE:omarchy-plugin-product-e2e-host>
      $<TARGET_FILE:omarchy-plugin-qml-worker>
      $<TARGET_FILE:omarchy-plugin-permission-store>
      "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product")
  set_tests_properties(plugin-product-e2e-bwrap PROPERTIES
    TIMEOUT 45 SKIP_RETURN_CODE 77
    LABELS "integration;product;e2e;security;real-bwrap;qml;broker;render"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")

  add_test(NAME plugin-host-version COMMAND omarchy-plugin-host --version)
  add_test(NAME plugin-host-preview-disabled
    COMMAND "${CMAKE_COMMAND}"
      -DHOST=$<TARGET_FILE:omarchy-plugin-host>
      -P "${CMAKE_CURRENT_SOURCE_DIR}/preview_disabled_test.cmake")
  add_test(NAME plugin-live-lab-provenance
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/../lab/provenance_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/../lab/omarchy-plugin-security-lab"
      "${CMAKE_BINARY_DIR}")
  set_tests_properties(plugin-host-version plugin-host-preview-disabled
    plugin-live-lab-provenance
    PROPERTIES TIMEOUT 10 LABELS "host;security;feature-gate")
endif()
