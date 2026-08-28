cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_surface_host LANGUAGES CXX)

include(CTest)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

option(PLUGIN_SECURITY_SURFACE_HOST_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer for D3" OFF)

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
if(NOT TARGET omarchy-plugin-render-session)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../render-session"
                   "${CMAKE_CURRENT_BINARY_DIR}/render-session")
endif()
if(NOT TARGET omarchy-plugin-trusted-bridge)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
                   "${CMAKE_CURRENT_BINARY_DIR}/trusted-bridge")
endif()

add_library(omarchy-plugin-surface-host STATIC surface_host.cpp)
omarchy_surface_host_defaults(omarchy-plugin-surface-host)
target_include_directories(omarchy-plugin-surface-host PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(omarchy-plugin-surface-host PUBLIC
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-manifest-contract
  omarchy-plugin-permission-contract
  omarchy-plugin-render-session
  omarchy-plugin-trusted-bridge)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-surface-host-test surface_host_test.cpp)
  omarchy_surface_host_defaults(omarchy-plugin-surface-host-test)
  target_compile_definitions(omarchy-plugin-surface-host-test PRIVATE
    D3_PRODUCT_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product")
  target_link_libraries(omarchy-plugin-surface-host-test PRIVATE
    omarchy-plugin-surface-host)
  add_test(NAME plugin-surface-host COMMAND omarchy-plugin-surface-host-test)
  set_tests_properties(plugin-surface-host PROPERTIES
    TIMEOUT 30
    LABELS "integration;adversarial;render;qml;input;security"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software")
endif()
