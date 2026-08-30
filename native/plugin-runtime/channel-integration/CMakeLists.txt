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

# Standalone builds validate the low transport target above. The native runtime
# root supplies host-session and is the authenticated composition build owner.
if(TARGET omarchy-plugin-host-session)
  add_library(omarchy-plugin-authenticated-session STATIC
    authenticated_session_channel.cpp
    broker_session_settlement.cpp
  )
  target_include_directories(omarchy-plugin-authenticated-session PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}"
  )
  omarchy_plugin_target_defaults(omarchy-plugin-authenticated-session)
  target_link_libraries(omarchy-plugin-authenticated-session PUBLIC
    omarchy-plugin-channel-integration
    omarchy-plugin-host-session
  )
  target_link_libraries(omarchy-plugin-authenticated-session PRIVATE Qt6::Core)
  set_target_properties(omarchy-plugin-authenticated-session PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
endif()

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

  if(TARGET omarchy-plugin-authenticated-session)
    add_executable(omarchy-plugin-authenticated-session-adapter-test
      authenticated_session_channel.cpp
      broker_session_settlement.cpp
      authenticated_session_channel_test.cpp
    )
    omarchy_plugin_target_defaults(
      omarchy-plugin-authenticated-session-adapter-test)
    target_compile_definitions(
      omarchy-plugin-authenticated-session-adapter-test PRIVATE
      OMARCHY_AUTHENTICATED_SESSION_CHANNEL_TESTING)
    target_link_libraries(
      omarchy-plugin-authenticated-session-adapter-test PRIVATE
      omarchy-plugin-channel-integration
      omarchy-plugin-host-session
      Qt6::Core)
    add_test(NAME plugin-authenticated-session-adapter
      COMMAND omarchy-plugin-authenticated-session-adapter-test)
    set_tests_properties(plugin-authenticated-session-adapter PROPERTIES
      TIMEOUT 30 LABELS "unit;security;session;adversarial")

    add_executable(omarchy-plugin-broker-session-settlement-test
      broker_session_settlement.cpp
      broker_session_settlement_test.cpp)
    omarchy_plugin_target_defaults(
      omarchy-plugin-broker-session-settlement-test)
    target_compile_definitions(
      omarchy-plugin-broker-session-settlement-test PRIVATE
      OMARCHY_BROKER_SETTLEMENT_TESTING)
    target_link_libraries(omarchy-plugin-broker-session-settlement-test PRIVATE
      omarchy-plugin-channel-integration omarchy-plugin-host-session)
    add_test(NAME plugin-broker-session-settlement
      COMMAND omarchy-plugin-broker-session-settlement-test)
    set_tests_properties(plugin-broker-session-settlement PROPERTIES
      TIMEOUT 30 LABELS "unit;security;session;broker;adversarial")

    add_executable(omarchy-plugin-authenticated-session-integration-test
      authenticated_session_integration_test.cpp)
    omarchy_plugin_target_defaults(
      omarchy-plugin-authenticated-session-integration-test)
    target_compile_definitions(
      omarchy-plugin-authenticated-session-integration-test PRIVATE
      CHANNEL_PEER_PATH="$<TARGET_FILE:omarchy-plugin-channel-peer>"
      FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
      BWRAP_PATH="/usr/bin/bwrap")
    target_link_libraries(
      omarchy-plugin-authenticated-session-integration-test PRIVATE
      omarchy-plugin-authenticated-session Qt6::Core)
    add_dependencies(omarchy-plugin-authenticated-session-integration-test
      omarchy-plugin-channel-peer omarchy-plugin-channel-fake-bwrap)
    add_test(NAME plugin-authenticated-session-integration-fake
      COMMAND omarchy-plugin-authenticated-session-integration-test fake)
    set_tests_properties(plugin-authenticated-session-integration-fake
      PROPERTIES TIMEOUT 30
      LABELS "integration;security;session;broker;launcher;adversarial")
    add_test(NAME plugin-authenticated-session-integration-bwrap
      COMMAND omarchy-plugin-authenticated-session-integration-test bwrap)
    set_tests_properties(plugin-authenticated-session-integration-bwrap
      PROPERTIES TIMEOUT 30 SKIP_RETURN_CODE 77
      LABELS "integration;security;session;broker;launcher;sandbox;linux")
  endif()
endif()
