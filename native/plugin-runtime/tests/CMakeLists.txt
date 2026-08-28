add_executable(omarchy-plugin-runtime-contract-test runtime_contract_test.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-runtime-contract-test)
target_link_libraries(omarchy-plugin-runtime-contract-test PRIVATE Qt6::Core Qt6::Qml Omarchy::PluginRuntimeVersion)

add_test(NAME plugin-runtime-protocol-version COMMAND omarchy-plugin-runtime-contract-test protocol)
set_tests_properties(plugin-runtime-protocol-version PROPERTIES LABELS "unit;protocol" TIMEOUT 10)

add_test(NAME plugin-runtime-version-reporting
  COMMAND omarchy-plugin-runtime-contract-test versions
    "$<TARGET_FILE:omarchy-plugin-host>"
    "$<TARGET_FILE:omarchy-plugin-qml-worker>"
)
set_tests_properties(plugin-runtime-version-reporting PROPERTIES LABELS "integration" TIMEOUT 10)

add_test(NAME plugin-runtime-direct-worker-denial
  COMMAND omarchy-plugin-runtime-contract-test worker-denial "$<TARGET_FILE:omarchy-plugin-qml-worker>"
)
set_tests_properties(plugin-runtime-direct-worker-denial PROPERTIES LABELS "adversarial" TIMEOUT 10)

add_test(NAME plugin-runtime-bridge-import
  COMMAND omarchy-plugin-runtime-contract-test bridge "${QT_QML_OUTPUT_DIRECTORY}"
)
set_tests_properties(plugin-runtime-bridge-import PROPERTIES LABELS "integration;qml" TIMEOUT 10)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/support/CMakeLists.txt")
  add_subdirectory(support)
endif()
