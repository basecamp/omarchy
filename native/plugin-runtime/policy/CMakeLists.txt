install(FILES data/builtin-capabilities-v1.json
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/policy")

# Runtime composition requires this trusted root even when no dynamic provider
# definitions ship in the package yet.
install(DIRECTORY DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/capabilities.d")

if(BUILD_TESTING)
  add_test(NAME plugin-builtin-capability-data
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/tests/builtin_capabilities_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/data/builtin-capabilities-v1.json"
      "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions/src/permission_contract.cpp")
  set_tests_properties(plugin-builtin-capability-data PROPERTIES
    TIMEOUT 10 LABELS "unit;policy;providers;schema")
endif()
