cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_channel_integration LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_CHANNEL_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(PLUGIN_SECURITY_CHANNEL_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core)

function(omarchy_plugin_target_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()
if(NOT TARGET omarchy-plugin-sandbox-policy)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/sandbox"
                   "${CMAKE_CURRENT_BINARY_DIR}/sandbox")
endif()
if(NOT TARGET omarchy-plugin-launcher)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../launcher"
                   "${CMAKE_CURRENT_BINARY_DIR}/launcher")
endif()
if(NOT TARGET omarchy-plugin-broker-core)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker")
endif()
if(NOT TARGET omarchy-plugin-surface-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface")
endif()

add_library(omarchy-plugin-channel-integration STATIC
  authenticated_channel.cpp
)
target_include_directories(omarchy-plugin-channel-integration PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
omarchy_plugin_target_defaults(omarchy-plugin-channel-integration)
target_link_libraries(omarchy-plugin-channel-integration PUBLIC
  Omarchy::PluginLauncher
  omarchy-plugin-broker-core
  omarchy-plugin-surface-contract
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-channel-peer channel_peer.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-channel-peer)
  target_link_libraries(omarchy-plugin-channel-peer PRIVATE
    omarchy-plugin-broker-core
    omarchy-plugin-surface-contract
  )

  add_executable(omarchy-plugin-channel-fake-bwrap fake_bwrap.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-channel-fake-bwrap)

  add_executable(omarchy-plugin-channel-integration-test
    authenticated_channel_test.cpp
  )
  omarchy_plugin_target_defaults(omarchy-plugin-channel-integration-test)
  target_link_libraries(omarchy-plugin-channel-integration-test PRIVATE
    omarchy-plugin-channel-integration
  )
  target_compile_definitions(omarchy-plugin-channel-integration-test PRIVATE
    CHANNEL_PEER_PATH="$<TARGET_FILE:omarchy-plugin-channel-peer>"
    FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
    BWRAP_PATH="/usr/bin/bwrap"
  )
  add_dependencies(omarchy-plugin-channel-integration-test
    omarchy-plugin-channel-peer
    omarchy-plugin-channel-fake-bwrap
  )

  add_test(NAME plugin-channel-integration-fake
    COMMAND omarchy-plugin-channel-integration-test fake
  )
  set_tests_properties(plugin-channel-integration-fake PROPERTIES
    TIMEOUT 30
    LABELS "unit;integration;adversarial;protocol;broker;launcher"
  )
  add_test(NAME plugin-channel-integration-bwrap
    COMMAND omarchy-plugin-channel-integration-test bwrap
  )
  set_tests_properties(plugin-channel-integration-bwrap PROPERTIES
    TIMEOUT 30
    SKIP_RETURN_CODE 77
    LABELS "integration;adversarial;protocol;broker;launcher;sandbox;linux"
  )
endif()
