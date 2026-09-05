cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_channel_integration LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_CHANNEL_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(PLUGIN_SECURITY_CHANNEL_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core DBus)

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
    src/desktop_notification_service.cpp
    src/plugin_permission_authority.cpp
    src/runtime_bootstrap.cpp
    src/activation_catalog.cpp
    src/runtime_roots.cpp
    src/plugin_runtime_root.cpp
    src/session_runtime_factory.cpp
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
    omarchy-plugin-discovery
    omarchy-plugin-provider-host
  )
  target_link_libraries(omarchy-plugin-authenticated-session PRIVATE
    Qt6::Core
    Qt6::DBus)
  set_target_properties(omarchy-plugin-authenticated-session PROPERTIES
    POSITION_INDEPENDENT_CODE ON)
  if(BUILD_TESTING)
    target_compile_definitions(omarchy-plugin-authenticated-session PUBLIC
      OMARCHY_PLUGIN_PERMISSION_AUTHORITY_TESTING)
  endif()
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
    Omarchy::PluginLauncherTestSupport
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
    LABELS "integration;adversarial;protocol;broker;launcher;sandbox;linux;security"
  )

  if(TARGET omarchy-plugin-authenticated-session)
    add_executable(omarchy-plugin-provider-composition-peer
      tests/helpers/provider_composition_peer.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-provider-composition-peer)

    add_executable(omarchy-plugin-provider-composition-test
      src/runtime_bootstrap.cpp
      src/runtime_roots.cpp
      tests/provider_composition_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-provider-composition-test)
    target_compile_definitions(omarchy-plugin-provider-composition-test PRIVATE
      OMARCHY_RUNTIME_BOOTSTRAP_TESTING
      OMARCHY_RUNTIME_ROOTS_TESTING
      PROVIDER_COMPOSITION_PEER_PATH="$<TARGET_FILE:omarchy-plugin-provider-composition-peer>")
    target_link_libraries(omarchy-plugin-provider-composition-test PRIVATE
      omarchy-plugin-authenticated-session Qt6::DBus)
    add_dependencies(omarchy-plugin-provider-composition-test
      omarchy-plugin-provider-composition-peer)
    add_test(NAME plugin-provider-composition
      COMMAND omarchy-plugin-provider-composition-test)
    set_tests_properties(plugin-provider-composition PROPERTIES
      TIMEOUT 30
      LABELS "integration;security;providers;bootstrap;protocol;filesystem;adversarial")
    find_program(OMARCHY_FAKEROOT_EXECUTABLE fakeroot)
    if(OMARCHY_FAKEROOT_EXECUTABLE AND
       NOT PLUGIN_SECURITY_CHANNEL_SANITIZERS)
      add_test(NAME plugin-provider-composition-ownership
        COMMAND "${OMARCHY_FAKEROOT_EXECUTABLE}" -u "${CMAKE_COMMAND}" -E env
          OMARCHY_TEST_FAKE_OWNERSHIP=1
          "$<TARGET_FILE:omarchy-plugin-provider-composition-test>")
      set_tests_properties(plugin-provider-composition-ownership PROPERTIES
        TIMEOUT 30
        LABELS "integration;security;providers;bootstrap;filesystem;adversarial;ownership")
    endif()

    add_executable(omarchy-plugin-desktop-notification-service-test
      tests/desktop_notification_service_test.cpp)
    omarchy_plugin_target_defaults(
      omarchy-plugin-desktop-notification-service-test)
    target_link_libraries(
      omarchy-plugin-desktop-notification-service-test PRIVATE
      omarchy-plugin-authenticated-session
      Qt6::Core
      Qt6::DBus)
    add_test(NAME plugin-desktop-notification-service
      COMMAND omarchy-plugin-desktop-notification-service-test)
    set_tests_properties(plugin-desktop-notification-service PROPERTIES
      TIMEOUT 10 LABELS "unit;security;providers;dbus")

    add_executable(omarchy-plugin-activation-catalog-test
      src/activation_catalog.cpp
      tests/activation_catalog_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-activation-catalog-test)
    target_link_libraries(omarchy-plugin-activation-catalog-test PRIVATE
      omarchy-plugin-activation-snapshot)
    add_test(NAME plugin-activation-catalog
      COMMAND omarchy-plugin-activation-catalog-test)
    set_tests_properties(plugin-activation-catalog PROPERTIES
      TIMEOUT 30 LABELS "unit;security;catalog;filesystem;adversarial")

    add_executable(omarchy-plugin-runtime-roots-test
      src/runtime_roots.cpp
      src/activation_catalog.cpp
      tests/runtime_roots_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-runtime-roots-test)
    target_compile_definitions(omarchy-plugin-runtime-roots-test PRIVATE
      OMARCHY_RUNTIME_ROOTS_TESTING)
    target_link_libraries(omarchy-plugin-runtime-roots-test PRIVATE
      omarchy-plugin-activation-snapshot
      omarchy-plugin-discovery
      omarchy-plugin-authenticated-session)
    add_test(NAME plugin-runtime-roots
      COMMAND omarchy-plugin-runtime-roots-test)
    set_tests_properties(plugin-runtime-roots PROPERTIES
      TIMEOUT 30 LABELS "unit;security;catalog;filesystem;adversarial")

    add_executable(omarchy-plugin-runtime-bootstrap-test
      src/runtime_bootstrap.cpp
      src/runtime_roots.cpp
      tests/runtime_bootstrap_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-runtime-bootstrap-test)
    target_compile_definitions(omarchy-plugin-runtime-bootstrap-test PRIVATE
      OMARCHY_RUNTIME_BOOTSTRAP_TESTING
      OMARCHY_RUNTIME_ROOTS_TESTING)
    target_link_libraries(omarchy-plugin-runtime-bootstrap-test PRIVATE
      omarchy-plugin-authenticated-session
      Qt6::DBus)
    add_test(NAME plugin-runtime-bootstrap
      COMMAND omarchy-plugin-runtime-bootstrap-test)
    set_tests_properties(plugin-runtime-bootstrap PROPERTIES
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

    add_executable(omarchy-plugin-product-session-test
      src/authenticated_session_channel.cpp
      src/broker_session_settlement.cpp
      src/plugin_permission_authority.cpp
      src/plugin_runtime_root.cpp
      src/session_runtime_factory.cpp
      tests/session_runtime_factory_test.cpp
      src/plugin_session.cpp
      tests/plugin_session_test.cpp)
    omarchy_plugin_target_defaults(omarchy-plugin-product-session-test)
    target_compile_definitions(omarchy-plugin-product-session-test PRIVATE
      OMARCHY_PLUGIN_SESSION_TESTING
      CHANNEL_PEER_PATH="$<TARGET_FILE:omarchy-plugin-channel-peer>"
      PROVIDER_COMPOSITION_PEER_PATH="$<TARGET_FILE:omarchy-plugin-provider-composition-peer>"
      FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
      QML_WORKER_PATH="$<TARGET_FILE:omarchy-plugin-qml-worker>"
      RUNTIME_ROOT_REVISION_FIXTURE="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/tests/fixtures/valid-minimal")
    target_link_libraries(omarchy-plugin-product-session-test PRIVATE
      omarchy-plugin-channel-integration omarchy-plugin-host-session
      Omarchy::PluginLauncherTestSupport Qt6::Core)
    target_link_libraries(omarchy-plugin-product-session-test PRIVATE
      omarchy-plugin-activation-snapshot)
    target_link_libraries(omarchy-plugin-product-session-test PRIVATE
      omarchy-plugin-provider-host)
    add_dependencies(omarchy-plugin-product-session-test
      omarchy-plugin-channel-peer omarchy-plugin-provider-composition-peer
      omarchy-plugin-channel-fake-bwrap
      omarchy-plugin-qml-worker)
    add_test(NAME plugin-product-session
      COMMAND omarchy-plugin-product-session-test)
    set_tests_properties(plugin-product-session PROPERTIES
      TIMEOUT 30 LABELS "unit;security;session;surface")
    add_test(NAME plugin-product-session-provider-settlement
      COMMAND omarchy-plugin-product-session-test --provider-settlement-only)
    set_tests_properties(plugin-product-session-provider-settlement PROPERTIES
      TIMEOUT 15
      LABELS "integration;security;session;providers;protocol")
    add_test(NAME plugin-product-session-real-worker-invalid-qml
      COMMAND omarchy-plugin-product-session-test
              --real-worker-invalid-qml-only)
    set_tests_properties(plugin-product-session-real-worker-invalid-qml
      PROPERTIES
        TIMEOUT 15
        SKIP_RETURN_CODE 77
        LABELS "integration;security;session;qml;sandbox"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    add_test(NAME plugin-product-session-real-worker-ordered-startup
      COMMAND omarchy-plugin-product-session-test
              --real-worker-valid-qml-only)
    set_tests_properties(plugin-product-session-real-worker-ordered-startup
      PROPERTIES
        TIMEOUT 15
        SKIP_RETURN_CODE 77
        LABELS "integration;security;session;qml;sandbox;startup"
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    add_test(NAME plugin-consent-only-classification
      COMMAND omarchy-plugin-product-session-test
              --consent-only-classification-only)
    set_tests_properties(plugin-consent-only-classification PROPERTIES
      TIMEOUT 15
      LABELS "unit;security;session;permissions;lifecycle")
    add_test(NAME plugin-product-session-required-denial
      COMMAND omarchy-plugin-product-session-test --required-denial-only)
    set_tests_properties(plugin-product-session-required-denial PROPERTIES
      TIMEOUT 15 LABELS "unit;security;session;authority")
    add_test(NAME plugin-runtime-root-fences
      COMMAND omarchy-plugin-product-session-test --runtime-root-fence-only)
    set_tests_properties(plugin-runtime-root-fences PROPERTIES
      TIMEOUT 15 LABELS "unit;security;session;authority")
  endif()
endif()
