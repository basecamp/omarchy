cmake_minimum_required(VERSION 3.24)
project(omarchy_plugin_capability_definitions LANGUAGES CXX)

if(NOT TARGET omarchy-plugin-permission-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permission-contract")
endif()

add_library(omarchy-plugin-capability-definitions STATIC
  src/capability_definition.cpp src/capability_definition_loader.cpp
  src/dynamic_activation.cpp)
target_include_directories(omarchy-plugin-capability-definitions PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(omarchy-plugin-capability-definitions PUBLIC
  omarchy-plugin-permission-contract)
target_compile_features(omarchy-plugin-capability-definitions PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-capability-definitions PRIVATE
  -Wall -Wextra -Wpedantic -Werror)

add_executable(omarchy-plugin-generate-capability-catalog
  tools/generate_builtin_catalog.cpp)
target_link_libraries(omarchy-plugin-generate-capability-catalog PRIVATE
  omarchy-plugin-capability-definitions)
target_compile_features(omarchy-plugin-generate-capability-catalog PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-generate-capability-catalog PRIVATE
  -Wall -Wextra -Wpedantic -Werror)

set(catalog_output "${CMAKE_CURRENT_BINARY_DIR}/catalog")
set(catalog_index "${catalog_output}/capability-catalog-v1.json")
set(catalog_definitions
  external.open-uri.https
  network.fetch
  system.observe
  device.observe
  device.control
  remote-account.read
  remote-account.write
  media.play-stream
  bash.execute)
set(catalog_files)
foreach(definition IN LISTS catalog_definitions)
  list(APPEND catalog_files
    "${catalog_output}/capabilities.d/${definition}.capability")
endforeach()
add_custom_command(
  OUTPUT ${catalog_index} ${catalog_files}
  COMMAND omarchy-plugin-generate-capability-catalog "${catalog_output}"
  DEPENDS omarchy-plugin-generate-capability-catalog
  VERBATIM)
add_custom_target(omarchy-plugin-capability-catalog ALL
  DEPENDS ${catalog_index} ${catalog_files})
install(FILES ${catalog_index}
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/metadata")
install(FILES ${catalog_files}
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/capabilities.d")

include(CTest)
if(BUILD_TESTING)
  add_executable(omarchy-plugin-capability-definition-test
    tests/capability_definition_test.cpp
    tests/capability_definition_loader_test.cpp
    tests/dynamic_activation_test.cpp
    tests/permissions_extensibility_contract_test.cpp)
  target_link_libraries(omarchy-plugin-capability-definition-test PRIVATE
    omarchy-plugin-capability-definitions)
  target_compile_features(omarchy-plugin-capability-definition-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-capability-definition-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)

  add_test(NAME capability-definition-contract
    COMMAND omarchy-plugin-capability-definition-test)
  set_tests_properties(capability-definition-contract PROPERTIES
    LABELS "security")
  add_test(NAME capability-catalog-determinism
    COMMAND "${CMAKE_COMMAND}"
      -DGENERATOR=$<TARGET_FILE:omarchy-plugin-generate-capability-catalog>
      -DGOLDEN_INDEX=${CMAKE_CURRENT_SOURCE_DIR}/tests/capability_catalog_golden.json
      -DOUTPUT=${CMAKE_CURRENT_BINARY_DIR}/catalog-repeat
      -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/verify_catalog.cmake)
endif()
