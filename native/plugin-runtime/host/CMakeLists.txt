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
target_link_libraries(omarchy-plugin-host PRIVATE omarchy-plugin-external-provider)

install(TARGETS omarchy-plugin-host RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")

if(BUILD_TESTING)
  qt_add_executable(omarchy-plugin-product-e2e-host main.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-product-e2e-host)
  target_compile_definitions(omarchy-plugin-product-e2e-host PRIVATE
    OMARCHY_PLUGIN_PRODUCT_E2E=1
    OMARCHY_PLUGIN_DYNAMIC_DEFINITION_ROOT="${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions")
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions")
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/network-fetch.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/network-fetch.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/media-play-stream.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/media-play-stream.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/device-observe.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/device-observe.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/device-control.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/device-control.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/remote-account-read.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/remote-account-read.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/remote-account-write.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/remote-account-write.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/external-open-uri.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/external-open-uri.capability" COPYONLY)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/system-observe.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions/system-observe.capability" COPYONLY)
  file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/network-definition")
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/network-fetch.capability"
    "${CMAKE_CURRENT_BINARY_DIR}/network-definition/network-fetch.capability" COPYONLY)
  add_executable(omarchy-plugin-dynamic-e2e-grant dynamic_e2e_grant.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-dynamic-e2e-grant)
  target_link_libraries(omarchy-plugin-dynamic-e2e-grant PRIVATE
    omarchy-plugin-grant-store omarchy-plugin-capability-definitions
    omarchy-plugin-providers omarchy-plugin-lifecycle)
  target_link_libraries(omarchy-plugin-product-e2e-host PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick
    Omarchy::PluginRuntimeVersion
    omarchy-plugin-product-host
    omarchy-plugin-broker-runtime
    omarchy-plugin-providers
    omarchy-plugin-lifecycle
    omarchy-plugin-audit-store)
  target_link_libraries(omarchy-plugin-product-e2e-host PRIVATE
    omarchy-plugin-external-provider)
  add_dependencies(omarchy-plugin-product-e2e-host
    omarchy-plugin-product-e2e-worker omarchy-plugin-permission-store)

  qt_add_executable(omarchy-plugin-radio-live-e2e-host main.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-radio-live-e2e-host)
  target_compile_definitions(omarchy-plugin-radio-live-e2e-host PRIVATE
    OMARCHY_PLUGIN_PRODUCT_E2E=1
    OMARCHY_PLUGIN_REAL_RADIO_E2E=1
    OMARCHY_PLUGIN_DYNAMIC_DEFINITION_ROOT="${CMAKE_CURRENT_BINARY_DIR}/dynamic-definitions")
  target_link_libraries(omarchy-plugin-radio-live-e2e-host PRIVATE
    Qt6::Core Qt6::Gui Qt6::Quick
    Omarchy::PluginRuntimeVersion
    omarchy-plugin-product-host
    omarchy-plugin-broker-runtime
    omarchy-plugin-providers
    omarchy-plugin-lifecycle
    omarchy-plugin-audit-store)
  target_link_libraries(omarchy-plugin-radio-live-e2e-host PRIVATE
    omarchy-plugin-external-provider)
  add_dependencies(omarchy-plugin-radio-live-e2e-host
    omarchy-plugin-product-e2e-worker omarchy-plugin-permission-store)
  add_test(NAME plugin-product-e2e-bwrap
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/product_e2e_test.sh"
      $<TARGET_FILE:omarchy-plugin-product-e2e-host>
      $<TARGET_FILE:omarchy-plugin-product-e2e-worker>
      $<TARGET_FILE:omarchy-plugin-permission-store>
      "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product"
      $<TARGET_FILE:omarchy-plugin-dynamic-e2e-grant>
      "${CMAKE_CURRENT_BINARY_DIR}/network-definition")
  set_tests_properties(plugin-product-e2e-bwrap PROPERTIES
    TIMEOUT 45 SKIP_RETURN_CODE 77
    LABELS "integration;product;e2e;security;real-bwrap;qml;broker;render"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")

  add_test(NAME plugin-production-worker-e2e-bwrap
    COMMAND "${CMAKE_COMMAND}" -E env
      OMARCHY_PLUGIN_E2E_ONLY_AUTHORIZED=1
      "${CMAKE_CURRENT_SOURCE_DIR}/product_e2e_test.sh"
      $<TARGET_FILE:omarchy-plugin-product-e2e-host>
      $<TARGET_FILE:omarchy-plugin-qml-worker>
      $<TARGET_FILE:omarchy-plugin-permission-store>
      "${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product"
      $<TARGET_FILE:omarchy-plugin-dynamic-e2e-grant>
      "${CMAKE_CURRENT_BINARY_DIR}/network-definition")
  set_tests_properties(plugin-production-worker-e2e-bwrap PROPERTIES
    TIMEOUT 20 SKIP_RETURN_CODE 77
    LABELS "integration;product;security;real-bwrap;qml;installed-style"
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
