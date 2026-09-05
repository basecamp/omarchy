cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_provider_host LANGUAGES CXX)

include(CTest)

find_package(PkgConfig REQUIRED)
pkg_check_modules(CURL REQUIRED IMPORTED_TARGET libcurl)

if(NOT TARGET omarchy-plugin-capability-definitions)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/capability-definitions"
                   "${CMAKE_CURRENT_BINARY_DIR}/capability-definitions")
endif()

add_library(omarchy-plugin-provider-host STATIC
  src/provider_catalog.cpp
  src/provider_host.cpp
)
target_compile_features(omarchy-plugin-provider-host PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-provider-host PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-provider-host PUBLIC include)
target_link_libraries(omarchy-plugin-provider-host PUBLIC
  omarchy-plugin-capability-definitions
  omarchy-plugin-launcher)

set(OMARCHY_COMMAND_CONTRACT_DIGEST
  "7cfb8547d49ea0d43248227c049f19d9f711c7838452789c9ef2fdfe41e82142")
set(OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST
  "d678287160034f2311446423b8c1d6847b80abc0ea62233036c578611387622c")
set(OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST
  "e32bc94a49b0e2170465f7e7c7d671a6a4a7d1d857cee4b4111b81dd3088c977")
set(OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST
  "24d172b971ac832c86d4e28c224bfd7e912aa1ea3de4517aa09af2c02d362a20")
set(OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST
  "f060bfec526a4355bd3431d39310bf96e61907f26be0e0dea6e6e8c2d28a415c")
configure_file(cmake/command_contract.hpp.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/command_contract.hpp" @ONLY)
add_executable(omarchy-plugin-command-executor
  src/command_executor.cpp)
target_compile_features(omarchy-plugin-command-executor PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-command-executor PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-command-executor PRIVATE
  "${CMAKE_CURRENT_BINARY_DIR}/generated")
target_link_libraries(omarchy-plugin-command-executor PRIVATE
  Qt6::Core)
install(TARGETS omarchy-plugin-command-executor
  RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")
add_executable(omarchy-plugin-desktop-opener
  src/desktop_open_provider.cpp)
target_compile_features(omarchy-plugin-desktop-opener PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-desktop-opener PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_compile_definitions(omarchy-plugin-desktop-opener PRIVATE
  OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST="${OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST}")
target_link_libraries(omarchy-plugin-desktop-opener PRIVATE Qt6::Core)
install(TARGETS omarchy-plugin-desktop-opener
  RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")
add_executable(omarchy-plugin-system-observer
  src/system_observe_provider.cpp)
target_compile_features(omarchy-plugin-system-observer PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-system-observer PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_compile_definitions(omarchy-plugin-system-observer PRIVATE
  OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST="${OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST}")
target_link_libraries(omarchy-plugin-system-observer PRIVATE Qt6::Core)
install(TARGETS omarchy-plugin-system-observer
  RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")
add_executable(omarchy-plugin-network-media-provider
  src/network_media_provider.cpp)
target_compile_features(omarchy-plugin-network-media-provider PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-network-media-provider PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_compile_definitions(omarchy-plugin-network-media-provider PRIVATE
  OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST="${OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST}"
  OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST="${OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST}")
target_link_libraries(omarchy-plugin-network-media-provider PRIVATE
  PkgConfig::CURL Qt6::Core)
install(TARGETS omarchy-plugin-network-media-provider
  RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")
install(FILES commands/github-api-v1.policy
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/commands.d")
configure_file(cmake/install_command_provider.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/install_command_provider.cmake" @ONLY)
install(SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/install_command_provider.cmake")
configure_file(cmake/install_desktop_open_provider.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/install_desktop_open_provider.cmake" @ONLY)
install(SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/install_desktop_open_provider.cmake")
configure_file(cmake/install_system_observe_provider.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/install_system_observe_provider.cmake" @ONLY)
install(SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/install_system_observe_provider.cmake")
configure_file(cmake/install_network_media_provider.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/install_network_media_provider.cmake" @ONLY)
install(SCRIPT "${CMAKE_CURRENT_BINARY_DIR}/install_network_media_provider.cmake")

if(BUILD_TESTING)
  find_package(Python3 REQUIRED COMPONENTS Interpreter)
  add_executable(omarchy-plugin-network-media-provider-test-peer
    src/network_media_provider.cpp)
  target_compile_features(omarchy-plugin-network-media-provider-test-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-network-media-provider-test-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-network-media-provider-test-peer PRIVATE
    OMARCHY_NETWORK_MEDIA_TESTING=1
    OMARCHY_PROVIDER_CHANNEL_FD=0
    OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST="${OMARCHY_NETWORK_FETCH_CONTRACT_DIGEST}"
    OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST="${OMARCHY_MEDIA_STREAM_CONTRACT_DIGEST}")
  target_link_libraries(omarchy-plugin-network-media-provider-test-peer PRIVATE
    PkgConfig::CURL Qt6::Core)
  add_test(NAME plugin-network-media-provider
    COMMAND ${Python3_EXECUTABLE}
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/network_media_provider_test.py
      $<TARGET_FILE:omarchy-plugin-network-media-provider-test-peer>)
  set_tests_properties(plugin-network-media-provider PROPERTIES
    TIMEOUT 10 LABELS "unit;security;providers;network;media;adversarial")

  add_executable(omarchy-plugin-command-executor-test-peer
    src/command_executor.cpp)
  target_compile_features(omarchy-plugin-command-executor-test-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-command-executor-test-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-command-executor-test-peer PRIVATE
    OMARCHY_COMMAND_EXECUTOR_TESTING=1)
  target_include_directories(omarchy-plugin-command-executor-test-peer PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/generated")
  target_link_libraries(omarchy-plugin-command-executor-test-peer PRIVATE
    Qt6::Core)

  add_executable(omarchy-plugin-command-executor-test
    tests/command_executor_test.cpp)
  target_compile_features(omarchy-plugin-command-executor-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-command-executor-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-command-executor-test PRIVATE
    COMMAND_EXECUTOR_PATH="$<TARGET_FILE:omarchy-plugin-command-executor-test-peer>"
    POLICY_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/tests/command-policies"
    BUILTIN_POLICY_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/commands"
    REJECTED_POLICY_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/tests/rejected-command-policies"
    MISSING_POLICY_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/tests/missing-command-policies")
  target_link_libraries(omarchy-plugin-command-executor-test PRIVATE Qt6::Core)
  add_dependencies(omarchy-plugin-command-executor-test
    omarchy-plugin-command-executor-test-peer)
  add_test(NAME plugin-command-executor
    COMMAND omarchy-plugin-command-executor-test)
  set_tests_properties(plugin-command-executor PROPERTIES
    TIMEOUT 10 LABELS "unit;security;providers;commands;adversarial")

  add_executable(omarchy-plugin-desktop-opener-test-peer
    src/desktop_open_provider.cpp)
  target_compile_features(omarchy-plugin-desktop-opener-test-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-desktop-opener-test-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-desktop-opener-test-peer PRIVATE
    OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST="${OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST}"
    OMARCHY_DESKTOP_OPEN_TESTING=1)
  target_link_libraries(omarchy-plugin-desktop-opener-test-peer PRIVATE Qt6::Core)

  add_executable(omarchy-plugin-desktop-opener-test
    tests/desktop_open_provider_test.cpp)
  target_compile_features(omarchy-plugin-desktop-opener-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-desktop-opener-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-desktop-opener-test PRIVATE
    DESKTOP_OPENER_PATH="$<TARGET_FILE:omarchy-plugin-desktop-opener-test-peer>"
    DESKTOP_OPEN_CONTRACT_DIGEST="${OMARCHY_DESKTOP_OPEN_CONTRACT_DIGEST}")
  target_link_libraries(omarchy-plugin-desktop-opener-test PRIVATE Qt6::Core)
  add_dependencies(omarchy-plugin-desktop-opener-test
    omarchy-plugin-desktop-opener-test-peer)
  add_test(NAME plugin-desktop-opener COMMAND omarchy-plugin-desktop-opener-test)
  set_tests_properties(plugin-desktop-opener PROPERTIES
    TIMEOUT 5 LABELS "unit;security;providers;desktop;gesture;adversarial")

  add_executable(omarchy-plugin-package-probe-test-peer
    tests/package_probe_peer.cpp)
  target_compile_features(omarchy-plugin-package-probe-test-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-package-probe-test-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  add_executable(omarchy-plugin-system-observer-test-peer
    src/system_observe_provider.cpp)
  target_compile_features(omarchy-plugin-system-observer-test-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-system-observer-test-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-system-observer-test-peer PRIVATE
    OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST="${OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST}"
    OMARCHY_SYSTEM_OBSERVE_CHECKUPDATES="$<TARGET_FILE:omarchy-plugin-package-probe-test-peer>"
    OMARCHY_SYSTEM_OBSERVE_PACMAN="$<TARGET_FILE:omarchy-plugin-package-probe-test-peer>"
    OMARCHY_SYSTEM_OBSERVE_HYPRCTL="$<TARGET_FILE:omarchy-plugin-package-probe-test-peer>"
    OMARCHY_SYSTEM_OBSERVE_TESTING=1)
  target_link_libraries(omarchy-plugin-system-observer-test-peer PRIVATE Qt6::Core)
  add_dependencies(omarchy-plugin-system-observer-test-peer
    omarchy-plugin-package-probe-test-peer)
  add_executable(omarchy-plugin-system-observer-test
    tests/system_observe_provider_test.cpp)
  target_compile_features(omarchy-plugin-system-observer-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-system-observer-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-system-observer-test PRIVATE
    SYSTEM_OBSERVER_PATH="$<TARGET_FILE:omarchy-plugin-system-observer-test-peer>"
    SYSTEM_OBSERVE_CONTRACT_DIGEST="${OMARCHY_SYSTEM_OBSERVE_CONTRACT_DIGEST}")
  target_link_libraries(omarchy-plugin-system-observer-test PRIVATE Qt6::Core)
  add_dependencies(omarchy-plugin-system-observer-test
    omarchy-plugin-system-observer-test-peer)
  add_test(NAME plugin-system-observer COMMAND omarchy-plugin-system-observer-test)
  set_tests_properties(plugin-system-observer PROPERTIES
    TIMEOUT 5 LABELS "unit;security;providers;system;privacy;adversarial")

  add_executable(omarchy-plugin-provider-peer tests/provider_peer.cpp)
  target_compile_features(omarchy-plugin-provider-peer PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-peer PRIVATE
    -Wall -Wextra -Wpedantic -Werror)

  add_executable(omarchy-plugin-provider-host-test tests/provider_host_test.cpp)
  target_compile_features(omarchy-plugin-provider-host-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-host-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-provider-host-test PRIVATE
    PROVIDER_PEER_PATH="$<TARGET_FILE:omarchy-plugin-provider-peer>")
  target_link_libraries(omarchy-plugin-provider-host-test PRIVATE
    omarchy-plugin-provider-host)
  add_dependencies(omarchy-plugin-provider-host-test
    omarchy-plugin-provider-peer)
  add_test(NAME plugin-provider-host COMMAND omarchy-plugin-provider-host-test)
  set_tests_properties(plugin-provider-host PROPERTIES
    TIMEOUT 30 LABELS "unit;security;providers;protocol;filesystem;adversarial")
  add_test(NAME plugin-provider-host-systemd-scope
    COMMAND omarchy-plugin-provider-host-test systemd)
  set_tests_properties(plugin-provider-host-systemd-scope PROPERTIES
    TIMEOUT 15 SKIP_RETURN_CODE 77
    LABELS "integration;security;providers;cgroup;adversarial")
endif()
