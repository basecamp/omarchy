cmake_minimum_required(VERSION 3.24)
project(omarchy_plugin_brokered_action LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_BROKERED_ACTION_SANITIZERS "Enable ASan/UBSan" OFF)
if(PLUGIN_SECURITY_BROKERED_ACTION_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Qml)
function(action_defaults target)
  target_compile_features(${target} PRIVATE cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

if(NOT TARGET omarchy-plugin-channel-integration)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration" "${CMAKE_CURRENT_BINARY_DIR}/channel")
endif()
if(NOT TARGET omarchy-plugin-broker-runtime)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker-runtime" "${CMAKE_CURRENT_BINARY_DIR}/runtime")
endif()

add_executable(omarchy-plugin-qml-action-peer qml_action_peer.cpp)
action_defaults(omarchy-plugin-qml-action-peer)
target_link_libraries(omarchy-plugin-qml-action-peer PRIVATE Qt6::Core Qt6::Qml omarchy-plugin-wire omarchy-plugin-broker-core omarchy-plugin-surface-contract)

add_executable(omarchy-plugin-brokered-action-test brokered_action_test.cpp)
action_defaults(omarchy-plugin-brokered-action-test)
target_link_libraries(omarchy-plugin-brokered-action-test PRIVATE omarchy-plugin-channel-integration omarchy-plugin-broker-runtime)
target_compile_definitions(omarchy-plugin-brokered-action-test PRIVATE
  QML_ACTION_PEER_PATH="$<TARGET_FILE:omarchy-plugin-qml-action-peer>"
  FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
  BWRAP_PATH="/usr/bin/bwrap"
)
add_dependencies(omarchy-plugin-brokered-action-test omarchy-plugin-qml-action-peer omarchy-plugin-channel-fake-bwrap)
add_test(NAME plugin-brokered-action COMMAND omarchy-plugin-brokered-action-test fake)
set_tests_properties(plugin-brokered-action PROPERTIES TIMEOUT 30 LABELS "integration;adversarial;qml;broker;audit;launcher")
add_test(NAME plugin-brokered-action-bwrap COMMAND omarchy-plugin-brokered-action-test bwrap)
set_tests_properties(plugin-brokered-action-bwrap PROPERTIES TIMEOUT 30 SKIP_RETURN_CODE 77 LABELS "integration;qml;broker;audit;launcher;sandbox;linux")
