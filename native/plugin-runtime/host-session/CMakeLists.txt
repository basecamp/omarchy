cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_host_session LANGUAGES CXX)
  include(CTest)
  find_package(Qt6 REQUIRED COMPONENTS Core)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permission-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/capability-definitions"
                   "${CMAKE_CURRENT_BINARY_DIR}/capability-definitions")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../providers"
                   "${CMAKE_CURRENT_BINARY_DIR}/providers")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker-runtime"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker-runtime")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../discovery"
                   "${CMAKE_CURRENT_BINARY_DIR}/discovery")
endif()

add_library(omarchy-plugin-activation-snapshot STATIC
  src/activation_snapshot.cpp
  src/authority_snapshot_codec.cpp
  src/authority_store.cpp
  src/consent_review.cpp
  src/permission_projection.cpp
  src/revision_verifier_adapter.cpp)
target_include_directories(omarchy-plugin-activation-snapshot PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../policy/src")
target_link_libraries(omarchy-plugin-activation-snapshot PUBLIC
  omarchy-plugin-permission-contract
  omarchy-plugin-capability-definitions
  omarchy-plugin-discovery
  omarchy-plugin-wire)
target_compile_features(omarchy-plugin-activation-snapshot PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-activation-snapshot PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
if(BUILD_TESTING)
  target_compile_definitions(omarchy-plugin-activation-snapshot PUBLIC
    OMARCHY_AUTHORITY_STORE_TESTING
    OMARCHY_REVISION_SOURCE_TESTING)
endif()

add_library(omarchy-plugin-host-session STATIC
  src/gesture_intent.cpp
  src/MultiSurfaceRouter.cpp
  src/plugin_session_io.cpp
  src/structured_broker.cpp)
target_include_directories(omarchy-plugin-host-session PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src")
target_link_libraries(omarchy-plugin-host-session PUBLIC
  Qt6::Core
  omarchy-plugin-surface-contract
  omarchy-plugin-broker-runtime
  omarchy-plugin-wire)
target_compile_features(omarchy-plugin-host-session PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-host-session PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
set_target_properties(omarchy-plugin-host-session PROPERTIES
  POSITION_INDEPENDENT_CODE ON)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-activation-snapshot-test tests/activation_snapshot_test.cpp)
  target_link_libraries(omarchy-plugin-activation-snapshot-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-activation-snapshot-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-activation-snapshot-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-activation-snapshot COMMAND omarchy-plugin-activation-snapshot-test)
  set_tests_properties(plugin-activation-snapshot PROPERTIES
    TIMEOUT 15 LABELS "unit;security;adversarial")

  add_executable(omarchy-plugin-revision-verifier-adapter-test
    tests/revision_verifier_adapter_test.cpp)
  target_link_libraries(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    cxx_std_20)
  target_compile_options(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-revision-verifier-adapter-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/tests/fixtures/valid-minimal")
  add_test(NAME plugin-revision-verifier-adapter
    COMMAND omarchy-plugin-revision-verifier-adapter-test)
  set_tests_properties(plugin-revision-verifier-adapter PROPERTIES
    TIMEOUT 15 LABELS "unit;security;adversarial")

  add_executable(omarchy-plugin-authority-store-test tests/authority_store_test.cpp)
  target_link_libraries(omarchy-plugin-authority-store-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-authority-store-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-authority-store-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-authority-store-test PRIVATE
    OMARCHY_AUTHORITY_STORE_TESTING)
  add_test(NAME plugin-authority-store COMMAND omarchy-plugin-authority-store-test)
  set_tests_properties(plugin-authority-store PROPERTIES
    TIMEOUT 20 LABELS "unit;security;authority;adversarial")
  add_test(NAME plugin-authority-store-crash-matrix
    COMMAND omarchy-plugin-authority-store-test --crash-matrix-only)
  set_tests_properties(plugin-authority-store-crash-matrix PROPERTIES
    TIMEOUT 20 LABELS "unit;security;authority;adversarial;crash")

  add_executable(omarchy-plugin-consent-review-test tests/consent_review_test.cpp)
  target_link_libraries(omarchy-plugin-consent-review-test PRIVATE
    omarchy-plugin-activation-snapshot)
  target_compile_features(omarchy-plugin-consent-review-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-consent-review-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-consent-review COMMAND omarchy-plugin-consent-review-test)
  set_tests_properties(plugin-consent-review PROPERTIES
    TIMEOUT 20 LABELS "unit;security;authority;consent;adversarial")

  add_executable(omarchy-plugin-multi-surface-router-test
    tests/MultiSurfaceRouter_test.cpp)
  target_link_libraries(omarchy-plugin-multi-surface-router-test PRIVATE
    omarchy-plugin-host-session)
  target_compile_features(omarchy-plugin-multi-surface-router-test PRIVATE
    cxx_std_20)
  target_compile_options(omarchy-plugin-multi-surface-router-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-multi-surface-router
    COMMAND omarchy-plugin-multi-surface-router-test)
  set_tests_properties(plugin-multi-surface-router PROPERTIES
    TIMEOUT 15 LABELS "unit;security;session")

  # Compile the lifecycle implementation separately so deterministic fault
  # hooks can never enter the trusted host-session archive.
  add_executable(omarchy-plugin-session-io-test
    src/plugin_session_io.cpp
    tests/plugin_session_io_test.cpp)
  target_link_libraries(omarchy-plugin-session-io-test PRIVATE Qt6::Core)
  target_include_directories(omarchy-plugin-session-io-test PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src")
  target_compile_features(omarchy-plugin-session-io-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-session-io-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-session-io-test PRIVATE
    OMARCHY_PLUGIN_SESSION_IO_TESTING)
  add_test(NAME plugin-session-io COMMAND omarchy-plugin-session-io-test)
  set_tests_properties(plugin-session-io PROPERTIES
    TIMEOUT 30 LABELS "unit;security;session;adversarial")

  add_executable(omarchy-plugin-structured-broker-test
    tests/structured_broker_test.cpp)
  target_link_libraries(omarchy-plugin-structured-broker-test PRIVATE
    omarchy-plugin-host-session)
  target_compile_features(omarchy-plugin-structured-broker-test PRIVATE
    cxx_std_20)
  target_compile_options(omarchy-plugin-structured-broker-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-structured-broker
    COMMAND omarchy-plugin-structured-broker-test)
  set_tests_properties(plugin-structured-broker PROPERTIES
    TIMEOUT 30 LABELS "unit;security;session;broker;adversarial")

  add_executable(omarchy-plugin-gesture-intent-test tests/gesture_intent_test.cpp)
  target_link_libraries(omarchy-plugin-gesture-intent-test PRIVATE
    omarchy-plugin-host-session)
  target_compile_features(omarchy-plugin-gesture-intent-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-gesture-intent-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_test(NAME plugin-gesture-intent COMMAND omarchy-plugin-gesture-intent-test)
  set_tests_properties(plugin-gesture-intent PROPERTIES
    TIMEOUT 10 LABELS "unit;security;session;gesture;adversarial")
endif()
