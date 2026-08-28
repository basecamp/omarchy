cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_embedded_bar_slice LANGUAGES CXX)

include(CTest)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

option(PLUGIN_SECURITY_E1_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer for E1" OFF)

if(PLUGIN_SECURITY_E1_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

function(omarchy_e1_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

if(NOT TARGET omarchy-plugin-surface-host)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../surface-host"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface-host")
endif()
if(NOT TARGET omarchy-plugin-broker-runtime)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../broker-runtime"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker-runtime")
endif()
if(NOT TARGET omarchy-plugin-channel-integration)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../channel-integration"
                   "${CMAKE_CURRENT_BINARY_DIR}/channel-integration")
endif()
if(NOT TARGET omarchy-plugin-supervisor-health)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../supervisor-health"
                   "${CMAKE_CURRENT_BINARY_DIR}/supervisor-health")
endif()

add_library(omarchy-plugin-e1-worker-runtime STATIC
  "${CMAKE_CURRENT_SOURCE_DIR}/../../worker/worker_runtime.cpp")
omarchy_e1_defaults(omarchy-plugin-e1-worker-runtime)
target_include_directories(omarchy-plugin-e1-worker-runtime PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/../../worker")
target_link_libraries(omarchy-plugin-e1-worker-runtime PUBLIC
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-surface-contract)

set(CMAKE_AUTOMOC ON)
add_executable(omarchy-plugin-embedded-bar-test embedded_bar_test.cpp)
omarchy_e1_defaults(omarchy-plugin-embedded-bar-test)
target_compile_definitions(omarchy-plugin-embedded-bar-test PRIVATE
  E1_POMODORO_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../../fixtures/product/pomodoro")
target_link_libraries(omarchy-plugin-embedded-bar-test PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-e1-worker-runtime
  omarchy-plugin-surface-host
  omarchy-plugin-broker-runtime
  omarchy-plugin-channel-integration
  omarchy-plugin-sandbox-policy)

add_test(NAME plugin-embedded-bar-slice
  COMMAND omarchy-plugin-embedded-bar-test)
set_tests_properties(plugin-embedded-bar-slice PROPERTIES
  TIMEOUT 30
  LABELS "vertical;integration;adversarial;render;qml;broker;sandbox;security"
  ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")
