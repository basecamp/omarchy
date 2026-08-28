add_executable(omarchy-plugin-launcher-probe launcher_probe.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-launcher-probe)

add_executable(omarchy-plugin-malicious-launcher-probe malicious_probe.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-malicious-launcher-probe)

add_executable(omarchy-plugin-fake-bwrap fake_bwrap.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-fake-bwrap)

add_executable(omarchy-plugin-duplicate-status-bwrap fake_bwrap.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-duplicate-status-bwrap)
target_compile_definitions(omarchy-plugin-duplicate-status-bwrap PRIVATE FAKE_DUPLICATE_STATUS=1)

add_executable(omarchy-plugin-string-status-bwrap fake_bwrap.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-string-status-bwrap)
target_compile_definitions(omarchy-plugin-string-status-bwrap PRIVATE FAKE_STRING_STATUS=1)

add_executable(omarchy-plugin-exited-status-bwrap fake_bwrap.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-exited-status-bwrap)
target_compile_definitions(omarchy-plugin-exited-status-bwrap PRIVATE FAKE_EXITED_STATUS=1)

add_executable(omarchy-plugin-launcher-test launcher_test.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-launcher-test)
target_link_libraries(omarchy-plugin-launcher-test PRIVATE
  Omarchy::PluginLauncher
  Omarchy::PluginTestSupport
)
target_compile_definitions(omarchy-plugin-launcher-test PRIVATE
  BWRAP_PATH="/usr/bin/bwrap"
  PROBE_PATH="$<TARGET_FILE:omarchy-plugin-launcher-probe>"
  MALICIOUS_PROBE_PATH="$<TARGET_FILE:omarchy-plugin-malicious-launcher-probe>"
  FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-fake-bwrap>"
  DUPLICATE_STATUS_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-duplicate-status-bwrap>"
  STRING_STATUS_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-string-status-bwrap>"
  EXITED_STATUS_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-exited-status-bwrap>"
)
add_dependencies(omarchy-plugin-launcher-test
  omarchy-plugin-launcher-probe
  omarchy-plugin-malicious-launcher-probe
  omarchy-plugin-fake-bwrap
  omarchy-plugin-duplicate-status-bwrap
  omarchy-plugin-string-status-bwrap
  omarchy-plugin-exited-status-bwrap
)

add_test(NAME plugin-launcher-contract COMMAND omarchy-plugin-launcher-test contract)
set_tests_properties(plugin-launcher-contract PROPERTIES LABELS "unit;adversarial;launcher" TIMEOUT 10)
add_test(NAME plugin-launcher-malicious-peer COMMAND omarchy-plugin-launcher-test malicious)
set_tests_properties(plugin-launcher-malicious-peer PROPERTIES LABELS "integration;adversarial;launcher;linux" TIMEOUT 10)
add_test(NAME plugin-launcher-bwrap COMMAND omarchy-plugin-launcher-test bwrap)
set_tests_properties(plugin-launcher-bwrap PROPERTIES LABELS "integration;adversarial;launcher;sandbox;linux" TIMEOUT 15 SKIP_RETURN_CODE 77)
add_test(NAME plugin-launcher-systemd-scope COMMAND omarchy-plugin-launcher-test systemd)
set_tests_properties(plugin-launcher-systemd-scope PROPERTIES LABELS "integration;adversarial;launcher;sandbox;cgroup;linux" TIMEOUT 15 SKIP_RETURN_CODE 77)
