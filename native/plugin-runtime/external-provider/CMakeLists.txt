add_library(omarchy-plugin-external-provider STATIC external_provider.cpp provider_registration.cpp)
target_include_directories(omarchy-plugin-external-provider PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(omarchy-plugin-external-provider PUBLIC omarchy-plugin-capability-definitions omarchy-plugin-audit-store Omarchy::PluginLauncher omarchy-plugin-grant-store omarchy-plugin-revision-store)
omarchy_plugin_target_defaults(omarchy-plugin-external-provider)

add_executable(omarchy-plugin-external-provider-test external_provider_test.cpp)
target_compile_definitions(omarchy-plugin-external-provider-test PRIVATE
  DYNAMIC_RADIO_FIXTURE="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product/lab-dynamic-radio"
  NETWORK_DEFINITION_FIXTURE="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/winners/definitions/network-fetch.capability")
target_link_libraries(omarchy-plugin-external-provider-test PRIVATE omarchy-plugin-external-provider)
omarchy_plugin_target_defaults(omarchy-plugin-external-provider-test)
add_test(NAME external-provider-e2e COMMAND omarchy-plugin-external-provider-test)

add_executable(omarchy-plugin-provider-admin provider_admin_cli.cpp)
target_link_libraries(omarchy-plugin-provider-admin PRIVATE
  omarchy-plugin-external-provider)
omarchy_plugin_target_defaults(omarchy-plugin-provider-admin)
install(TARGETS omarchy-plugin-provider-admin
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
install(DIRECTORY DESTINATION
  "${CMAKE_INSTALL_SYSCONFDIR}/omarchy/plugin-providers.d"
  DIRECTORY_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
                        GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
install(DIRECTORY DESTINATION
  "${CMAKE_INSTALL_LOCALSTATEDIR}/lib/omarchy/plugin-security"
  DIRECTORY_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-provider-admin-test provider_admin_cli.cpp)
  target_compile_definitions(omarchy-plugin-provider-admin-test PRIVATE
    OMARCHY_PROVIDER_ADMIN_TESTING=1)
  target_link_libraries(omarchy-plugin-provider-admin-test PRIVATE
    omarchy-plugin-external-provider)
  omarchy_plugin_target_defaults(omarchy-plugin-provider-admin-test)
  add_test(NAME external-provider-admin-cli
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/provider_admin_cli_test.sh"
      $<TARGET_FILE:omarchy-plugin-provider-admin-test>)
  set_tests_properties(external-provider-admin-cli PROPERTIES
    TIMEOUT 15 LABELS "integration;product;e2e;security;provider;lifecycle")
endif()
