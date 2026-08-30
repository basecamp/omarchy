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

include(CTest)
if(BUILD_TESTING)
  add_executable(omarchy-plugin-capability-definition-test
    tests/capability_definition_test.cpp
    tests/capability_definition_loader_test.cpp
    tests/dynamic_activation_test.cpp
    tests/permissions_extensibility_demo_test.cpp)
  target_link_libraries(omarchy-plugin-capability-definition-test PRIVATE
    omarchy-plugin-capability-definitions)
  target_compile_features(omarchy-plugin-capability-definition-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-capability-definition-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)

  add_test(NAME capability-definition-contract
    COMMAND omarchy-plugin-capability-definition-test)
endif()
