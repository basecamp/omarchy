add_library(omarchy-plugin-external-provider STATIC external_provider.cpp provider_registration.cpp)
target_include_directories(omarchy-plugin-external-provider PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(omarchy-plugin-external-provider PUBLIC omarchy-plugin-capability-definitions omarchy-plugin-audit-store Omarchy::PluginLauncher)
omarchy_plugin_target_defaults(omarchy-plugin-external-provider)

add_executable(omarchy-plugin-external-provider-test external_provider_test.cpp)
target_link_libraries(omarchy-plugin-external-provider-test PRIVATE omarchy-plugin-external-provider)
omarchy_plugin_target_defaults(omarchy-plugin-external-provider-test)
add_test(NAME external-provider-e2e COMMAND omarchy-plugin-external-provider-test)
