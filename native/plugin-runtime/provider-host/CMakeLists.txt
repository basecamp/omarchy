cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_provider_host LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-capability-definitions)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/capability-definitions"
                   "${CMAKE_CURRENT_BINARY_DIR}/capability-definitions")
endif()

add_library(omarchy-plugin-provider-host STATIC
  src/provider_host.cpp
)
target_compile_features(omarchy-plugin-provider-host PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-provider-host PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-provider-host PUBLIC include)
target_link_libraries(omarchy-plugin-provider-host PUBLIC
  omarchy-plugin-capability-definitions)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-provider-peer tests/provider_peer.cpp)
  target_compile_features(omarchy-plugin-provider-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)

  add_executable(omarchy-plugin-provider-host-test tests/provider_host_test.cpp)
  target_compile_features(omarchy-plugin-provider-host-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-host-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-provider-host-test PRIVATE
    PROVIDER_PEER_PATH="$<TARGET_FILE:omarchy-plugin-provider-peer>")
  target_link_libraries(omarchy-plugin-provider-host-test PRIVATE
    omarchy-plugin-provider-host)
  add_dependencies(omarchy-plugin-provider-host-test
    omarchy-plugin-provider-peer)
  add_test(NAME plugin-provider-host COMMAND omarchy-plugin-provider-host-test)
  set_tests_properties(plugin-provider-host PROPERTIES
    TIMEOUT 30 LABELS "unit;security;providers;protocol;filesystem;adversarial")
endif()
