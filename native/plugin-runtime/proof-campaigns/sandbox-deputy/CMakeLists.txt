cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_f0_sandbox_deputy LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_F0_SANITIZERS
       "Enable sanitizers throughout the F0 proof campaign" OFF)
if(PLUGIN_SECURITY_F0_SANITIZERS)
  set(PLUGIN_SECURITY_ENABLE_SANITIZERS ON CACHE BOOL "" FORCE)
  set(PLUGIN_SECURITY_CHANNEL_SANITIZERS ON CACHE BOOL "" FORCE)
  set(PLUGIN_SECURITY_BROKERED_ACTION_SANITIZERS ON CACHE BOOL "" FORCE)
endif()

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../tests/adversarial"
                 "${CMAKE_CURRENT_BINARY_DIR}/adversarial")
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../brokered-action"
                 "${CMAKE_CURRENT_BINARY_DIR}/brokered-action")

add_custom_target(omarchy-plugin-f0-proof
  DEPENDS
    omarchy-plugin-adversarial-harness-test
    omarchy-plugin-channel-integration-test
    omarchy-plugin-brokered-action-test
)
