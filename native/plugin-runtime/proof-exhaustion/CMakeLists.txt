cmake_minimum_required(VERSION 3.24)
project(omarchy_plugin_exhaustion_proof LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_F1_SANITIZERS "Enable ASan/UBSan for the F1 tree" OFF)
if(PLUGIN_SECURITY_F1_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

if(NOT TARGET omarchy-plugin-embedded-bar-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../vertical-slices/embedded-bar" e1)
endif()
if(NOT TARGET omarchy-plugin-headless-slice-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../headless-slice" e0)
endif()
if(NOT TARGET omarchy-plugin-expressive-surface-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../expressive-surface" e2)
endif()
if(NOT TARGET omarchy-plugin-brokered-action-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../brokered-action" e3)
endif()
if(NOT TARGET omarchy-plugin-adversarial-harness-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../tests/adversarial" adversarial)
endif()

add_executable(omarchy-plugin-exhaustion-proof-test exhaustion_proof_test.cpp)
target_compile_features(omarchy-plugin-exhaustion-proof-test PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-exhaustion-proof-test PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(omarchy-plugin-exhaustion-proof-test PRIVATE
  omarchy-plugin-wire
  omarchy-plugin-surface-contract
  omarchy-plugin-broker-core
  omarchy-plugin-sandbox-policy)
add_test(NAME plugin-exhaustion-proof COMMAND omarchy-plugin-exhaustion-proof-test)
set_tests_properties(plugin-exhaustion-proof PROPERTIES
  TIMEOUT 30
  LABELS "proof;stress;adversarial;protocol;resources;security")
