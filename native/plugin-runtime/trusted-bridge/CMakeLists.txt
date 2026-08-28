cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_trusted_bridge LANGUAGES CXX)

include(CTest)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

if(NOT TARGET omarchy-plugin-surface-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface")
endif()

qt_add_library(omarchy-plugin-trusted-bridge STATIC)
qt_add_qml_module(omarchy-plugin-trusted-bridge
  URI Omarchy.PluginHost
  VERSION 1.0
  OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/Omarchy/PluginHost"
  SOURCES
    remote_surface.cpp
    remote_surface.hpp
    render_input_transport.cpp
    render_input_transport.hpp
)
target_compile_features(omarchy-plugin-trusted-bridge PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-trusted-bridge PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-trusted-bridge PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(omarchy-plugin-trusted-bridge PUBLIC
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick omarchy-plugin-surface-contract
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-trusted-bridge-test trusted_bridge_test.cpp)
  target_compile_features(omarchy-plugin-trusted-bridge-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-trusted-bridge-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-trusted-bridge-test PRIVATE omarchy-plugin-trusted-bridge Qt6::Gui Qt6::Quick)
  add_test(NAME plugin-trusted-bridge COMMAND omarchy-plugin-trusted-bridge-test)
  set_tests_properties(plugin-trusted-bridge PROPERTIES
    TIMEOUT 30
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME="
    LABELS "unit;integration;adversarial;render;qml"
  )
endif()
