if(BUILD_TESTING)
  add_test(NAME plugin-quickshell-io-compatibility-boundary
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/compatibility_boundary_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/qml")
  set_tests_properties(plugin-quickshell-io-compatibility-boundary PROPERTIES
    TIMEOUT 5 LABELS "qml;quickshell-compat;security;api-snapshot")
endif()
