add_library(omarchy-plugin-sandbox-policy STATIC src/policy.cpp)
add_library(Omarchy::PluginSandboxPolicy ALIAS omarchy-plugin-sandbox-policy)

omarchy_plugin_target_defaults(omarchy-plugin-sandbox-policy)
target_include_directories(omarchy-plugin-sandbox-policy PUBLIC include)

if(BUILD_TESTING)
  find_package(PkgConfig REQUIRED)
  pkg_check_modules(SECCOMP REQUIRED IMPORTED_TARGET libseccomp)

  add_executable(omarchy-plugin-sandbox-policy-test tests/policy_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sandbox-policy-test)
  target_link_libraries(omarchy-plugin-sandbox-policy-test PRIVATE Omarchy::PluginSandboxPolicy)
  add_test(NAME plugin-sandbox-policy COMMAND omarchy-plugin-sandbox-policy-test)
  set_tests_properties(plugin-sandbox-policy PROPERTIES LABELS "unit;adversarial;sandbox" TIMEOUT 10)

  add_executable(omarchy-plugin-sandbox-probe tests/sandbox_probe.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sandbox-probe)

  add_executable(omarchy-plugin-sandbox-enforcement-test tests/enforcement_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sandbox-enforcement-test)
  target_link_libraries(omarchy-plugin-sandbox-enforcement-test PRIVATE Omarchy::PluginSandboxPolicy)
  target_link_libraries(omarchy-plugin-sandbox-enforcement-test PRIVATE PkgConfig::SECCOMP)
  target_compile_definitions(omarchy-plugin-sandbox-enforcement-test PRIVATE
    SANDBOX_PROBE_PATH="$<TARGET_FILE:omarchy-plugin-sandbox-probe>"
  )
  add_dependencies(omarchy-plugin-sandbox-enforcement-test omarchy-plugin-sandbox-probe)
  add_test(NAME plugin-sandbox-enforcement COMMAND omarchy-plugin-sandbox-enforcement-test)
  set_tests_properties(plugin-sandbox-enforcement PROPERTIES LABELS "integration;adversarial;sandbox" TIMEOUT 15 SKIP_RETURN_CODE 77)
endif()
