cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_host_session LANGUAGES CXX)
  include(CTest)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permission-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/capability-definitions"
                   "${CMAKE_CURRENT_BINARY_DIR}/capability-definitions")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../discovery"
                   "${CMAKE_CURRENT_BINARY_DIR}/discovery")
endif()

add_library(omarchy-plugin-activation-snapshot STATIC
  activation_snapshot.cpp
  revision_verifier_adapter.cpp)
target_include_directories(omarchy-plugin-activation-snapshot PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../policy")
target_link_libraries(omarchy-plugin-activation-snapshot PUBLIC
  omarchy-plugin-permission-contract
  omarchy-plugin-capability-definitions
  omarchy-plugin-discovery)
target_compile_features(omarchy-plugin-activation-snapshot PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-activation-snapshot PRIVATE
  -Wall -Wextra -Wpedantic -Werror)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-activation-snapshot-test activation_snapshot_test.cpp)
  target_link_libraries(omarchy-plugin-activation-snapshot-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-activation-snapshot-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-activation-snapshot-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-activation-snapshot COMMAND omarchy-plugin-activation-snapshot-test)
  set_tests_properties(plugin-activation-snapshot PROPERTIES
    TIMEOUT 15 LABELS "unit;security;adversarial")

  add_executable(omarchy-plugin-revision-verifier-adapter-test
    revision_verifier_adapter_test.cpp)
  target_link_libraries(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    cxx_std_20)
  target_compile_options(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal")
  add_test(NAME plugin-revision-verifier-adapter
    COMMAND omarchy-plugin-revision-verifier-adapter-test)
  set_tests_properties(plugin-revision-verifier-adapter PROPERTIES
    TIMEOUT 15 LABELS "unit;security;adversarial")
endif()
