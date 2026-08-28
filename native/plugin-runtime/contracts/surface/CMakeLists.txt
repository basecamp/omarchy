cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_surface_contract LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire-dependency")
endif()

add_library(omarchy-plugin-surface-contract STATIC
  src/frame_region.cpp
  src/frame_transport.cpp
  src/input.cpp
  src/profile.cpp
  src/render_messages.cpp
  src/shared_layout.cpp
  src/surface_state.cpp
)
target_compile_features(omarchy-plugin-surface-contract PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-surface-contract PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-surface-contract PUBLIC include)
target_link_libraries(omarchy-plugin-surface-contract PUBLIC omarchy-plugin-wire)

if(BUILD_TESTING)
  foreach(test_name IN ITEMS layout frame_region publication surface_state input profile bridge_contract)
    add_executable(plugin-surface-${test_name}-test tests/${test_name}_test.cpp)
    target_link_libraries(plugin-surface-${test_name}-test PRIVATE omarchy-plugin-surface-contract)
    target_compile_options(plugin-surface-${test_name}-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
    add_test(NAME plugin-surface-${test_name} COMMAND plugin-surface-${test_name}-test)
    set_tests_properties(plugin-surface-${test_name} PROPERTIES LABELS "unit;render")
  endforeach()
  set_tests_properties(plugin-surface-publication PROPERTIES LABELS "adversarial;property;render")
  set_tests_properties(plugin-surface-frame_region PROPERTIES LABELS "adversarial;integration;render")
  set_tests_properties(plugin-surface-layout PROPERTIES LABELS "property;render")
  set_tests_properties(plugin-surface-input PROPERTIES LABELS "adversarial;render")
  set_tests_properties(plugin-surface-profile PROPERTIES LABELS "integration;protocol;render")
endif()
