if(BUILD_TESTING)
  add_test(NAME plugin-quickshell-compatibility-authority-boundary
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/compatibility_boundary_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}")
  set_tests_properties(plugin-quickshell-compatibility-authority-boundary PROPERTIES
    TIMEOUT 5 LABELS "qml;compatibility;security;api-snapshot")
endif()
