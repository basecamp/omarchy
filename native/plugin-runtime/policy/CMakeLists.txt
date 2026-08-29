install(FILES data/builtin-capabilities-v1.json
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/policy")

if(BUILD_TESTING)
  add_test(NAME plugin-builtin-capability-data
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/builtin_capabilities_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/data/builtin-capabilities-v1.json"
      "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions/permission_contract.cpp")
  set_tests_properties(plugin-builtin-capability-data PROPERTIES
    TIMEOUT 10 LABELS "unit;policy;providers;schema")
endif()
