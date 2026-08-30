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
  target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
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
  src/authenticated_channel.cpp
)
target_include_directories(omarchy-plugin-channel-integration PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
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
    src/authenticated_session_channel.cpp
    src/broker_session_settlement.cpp
    src/plugin_activation_coordinator.cpp
    src/plugin_permission_controller.cpp
    src/production_plugin_bootstrap.cpp
    src/production_plugin_catalog.cpp
    src/production_plugin_roots.cpp
    src/production_plugin_runtime_root.cpp
    src/production_session_runtime_factory.cpp
    src/plugin_session.cpp
  )
  target_include_directories(omarchy-plugin-authenticated-session PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
  )
  omarchy_plugin_target_defaults(omarchy-plugin-authenticated-session)
  target_link_libraries(omarchy-plugin-authenticated-session PUBLIC
    omarchy-plugin-channel-integration
    omarchy-plugin-activation-snapshot
    omarchy-plugin-host-session
  )
  target_link_libraries(omarchy-plugin-authenticated-session PRIVATE Qt6::Core)
  set_target_properties(omarchy-plugin-authenticated-session PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-channel-peer tests/helpers/channel_peer.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-channel-peer)
  target_link_libraries(omarchy-plugin-channel-peer PRIVATE
    omarchy-plugin-broker-core
    omarchy-plugin-surface-contract
  )

  add_executable(omarchy-plugin-channel-fake-bwrap tests/helpers/fake_bwrap.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-channel-fake-bwrap)

  add_executable(omarchy-plugin-channel-integration-test
    tests/authenticated_channel_test.cpp
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
    add_executable(omarchy-plugin-production-catalog-test
      src/production_plugin_catalog.cpp
      tests/production_plugin_catalog_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-production-catalog-test)
    target_link_libraries(omarchy-plugin-production-catalog-test PRIVATE
      omarchy-plugin-activation-snapshot)
    add_test(NAME plugin-production-catalog
      COMMAND omarchy-plugin-production-catalog-test)
    set_tests_properties(plugin-production-catalog PROPERTIES
      TIMEOUT 30 LABELS "unit;security;catalog;filesystem;adversarial")

    add_executable(omarchy-plugin-production-roots-test
      src/production_plugin_roots.cpp
      tests/production_plugin_roots_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-production-roots-test)
    target_compile_definitions(omarchy-plugin-production-roots-test PRIVATE
      OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING)
    target_link_libraries(omarchy-plugin-production-roots-test PRIVATE
      omarchy-plugin-activation-snapshot)
    add_test(NAME plugin-production-roots
      COMMAND omarchy-plugin-production-roots-test)
    set_tests_properties(plugin-production-roots PROPERTIES
      TIMEOUT 30 LABELS "unit;security;catalog;filesystem;adversarial")

    add_executable(omarchy-plugin-production-bootstrap-test
      src/production_plugin_bootstrap.cpp
      src/production_plugin_roots.cpp
      tests/production_plugin_bootstrap_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-production-bootstrap-test)
    target_compile_definitions(omarchy-plugin-production-bootstrap-test PRIVATE
      OMARCHY_PRODUCTION_PLUGIN_BOOTSTRAP_TESTING
      OMARCHY_PRODUCTION_PLUGIN_ROOTS_TESTING)
    target_link_libraries(omarchy-plugin-production-bootstrap-test PRIVATE
      omarchy-plugin-authenticated-session)
    add_test(NAME plugin-production-bootstrap
      COMMAND omarchy-plugin-production-bootstrap-test)
    set_tests_properties(plugin-production-bootstrap PROPERTIES
      TIMEOUT 30 LABELS "unit;security;bootstrap;filesystem;adversarial")

    add_executable(omarchy-plugin-authenticated-session-adapter-test
      src/authenticated_session_channel.cpp
      src/broker_session_settlement.cpp
      tests/authenticated_session_channel_test.cpp
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
      src/broker_session_settlement.cpp
      tests/broker_session_settlement_test.cpp)
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
      tests/authenticated_session_integration_test.cpp)
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

    add_executable(omarchy-plugin-product-session-test
      src/authenticated_session_channel.cpp
      src/broker_session_settlement.cpp
      src/plugin_activation_coordinator.cpp
      src/plugin_permission_controller.cpp
      src/production_plugin_runtime_root.cpp
      src/production_session_runtime_factory.cpp
      tests/production_session_runtime_factory_test.cpp
      src/plugin_session.cpp
      tests/plugin_session_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-product-session-test)
    target_compile_definitions(omarchy-plugin-product-session-test PRIVATE
      OMARCHY_PLUGIN_SESSION_TESTING
      CHANNEL_PEER_PATH="$<TARGET_FILE:omarchy-plugin-channel-peer>"
      FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
      COORDINATOR_REVISION_FIXTURE="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/tests/fixtures/valid-minimal")
    target_link_libraries(omarchy-plugin-product-session-test PRIVATE
      omarchy-plugin-channel-integration omarchy-plugin-host-session Qt6::Core)
    target_link_libraries(omarchy-plugin-product-session-test PRIVATE
      omarchy-plugin-activation-snapshot)
    add_dependencies(omarchy-plugin-product-session-test
      omarchy-plugin-channel-peer omarchy-plugin-channel-fake-bwrap)
    add_test(NAME plugin-product-session
      COMMAND omarchy-plugin-product-session-test)
    set_tests_properties(plugin-product-session PROPERTIES
      TIMEOUT 30 LABELS "unit;security;session;surface")
  endif()
endif()
