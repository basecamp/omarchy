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
  add_test(NAME plugin-host-version COMMAND omarchy-plugin-host --version)
  add_test(NAME plugin-host-preview-disabled
    COMMAND "${CMAKE_COMMAND}"
      -DHOST=$<TARGET_FILE:omarchy-plugin-host>
      -P "${CMAKE_CURRENT_SOURCE_DIR}/preview_disabled_test.cmake")
  set_tests_properties(plugin-host-version plugin-host-preview-disabled
    PROPERTIES TIMEOUT 10 LABELS "host;security;feature-gate")
endif()
