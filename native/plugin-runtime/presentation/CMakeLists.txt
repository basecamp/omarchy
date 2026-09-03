if(BUILD_TESTING)
  add_test(NAME plugin-presentation-authority-boundary
    COMMAND "${CMAKE_CURRENT_SOURCE_DIR}/presentation_boundary_test.sh"
      "${CMAKE_CURRENT_SOURCE_DIR}/qml")
  set_tests_properties(plugin-presentation-authority-boundary PROPERTIES
    TIMEOUT 5 LABELS "qml;presentation;security;api-snapshot")
endif()
