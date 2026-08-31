cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_surface_host LANGUAGES CXX)

include(CTest)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

option(PLUGIN_SECURITY_SURFACE_HOST_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer for surface host" OFF)

function(omarchy_surface_host_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  if(PLUGIN_SECURITY_SURFACE_HOST_SANITIZERS)
    target_compile_options(${target} PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

if(NOT TARGET omarchy-plugin-manifest-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest")
endif()
if(NOT TARGET omarchy-plugin-permission-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permissions")
endif()
if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()
if(NOT TARGET omarchy-plugin-surface-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface")
endif()
if(NOT TARGET omarchy-plugin-trusted-bridge)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
                   "${CMAKE_CURRENT_BINARY_DIR}/trusted-bridge")
endif()

add_library(omarchy-plugin-surface-host STATIC
  src/render_session.cpp
  src/surface_host.cpp)
omarchy_surface_host_defaults(omarchy-plugin-surface-host)
target_include_directories(omarchy-plugin-surface-host PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(omarchy-plugin-surface-host PUBLIC
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-manifest-contract
  omarchy-plugin-permission-contract
  omarchy-plugin-surface-contract
  omarchy-plugin-trusted-bridge
  omarchy-plugin-wire)

if(BUILD_TESTING)
  find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)

  add_executable(omarchy-plugin-surface-host-test tests/surface_host_test.cpp)
  omarchy_surface_host_defaults(omarchy-plugin-surface-host-test)
  target_link_libraries(omarchy-plugin-surface-host-test PRIVATE
    omarchy-plugin-surface-host)
  add_test(NAME plugin-surface-host COMMAND omarchy-plugin-surface-host-test)
  set_tests_properties(plugin-surface-host PROPERTIES
    TIMEOUT 30
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME="
    LABELS "unit;integration;adversarial;render;qml")

  add_executable(omarchy-plugin-surface-host-render-session-test
    tests/render_session_test.cpp)
  set_target_properties(omarchy-plugin-surface-host-render-session-test PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
  omarchy_surface_host_defaults(omarchy-plugin-surface-host-render-session-test)
  target_include_directories(omarchy-plugin-surface-host-render-session-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../worker/src")
  target_compile_definitions(omarchy-plugin-surface-host-render-session-test PRIVATE
    SURFACE_HOST_WORKER_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../worker/tests/fixtures")
  target_link_libraries(omarchy-plugin-surface-host-render-session-test PRIVATE
    omarchy-plugin-surface-host
    omarchy-plugin-worker-runtime
    Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::Qml Qt6::Quick)
  add_test(NAME plugin-render-session
    COMMAND omarchy-plugin-surface-host-render-session-test)
  set_tests_properties(plugin-render-session PROPERTIES
    TIMEOUT 30
    LABELS "integration;adversarial;render;qml;protocol;security"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")
endif()
