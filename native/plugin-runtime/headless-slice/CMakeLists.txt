cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_headless_slice LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_HEADLESS_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

find_package(Qt6 REQUIRED COMPONENTS Core)

if(NOT TARGET omarchy-plugin-channel-integration)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration"
                   "${CMAKE_CURRENT_BINARY_DIR}/channel-integration")
endif()
if(NOT TARGET omarchy-plugin-supervisor-health)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../supervisor-health"
                   "${CMAKE_CURRENT_BINARY_DIR}/supervisor-health")
endif()

add_library(omarchy-plugin-headless-slice STATIC headless_slice.cpp)
target_include_directories(omarchy-plugin-headless-slice PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-headless-slice PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-headless-slice PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-headless-slice PUBLIC
  omarchy-plugin-channel-integration
  omarchy-plugin-supervisor-health
)

if(PLUGIN_SECURITY_HEADLESS_SANITIZERS)
  target_compile_options(omarchy-plugin-headless-slice PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-headless-slice PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-headless-slice-test headless_slice_test.cpp)
  target_compile_features(omarchy-plugin-headless-slice-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-headless-slice-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-headless-slice-test PRIVATE
    omarchy-plugin-headless-slice
  )
  target_compile_definitions(omarchy-plugin-headless-slice-test PRIVATE
    CHANNEL_PEER_PATH="$<TARGET_FILE:omarchy-plugin-channel-peer>"
    FAKE_BWRAP_PATH="$<TARGET_FILE:omarchy-plugin-channel-fake-bwrap>"
    BWRAP_PATH="/usr/bin/bwrap"
  )
  add_dependencies(omarchy-plugin-headless-slice-test
    omarchy-plugin-channel-peer
    omarchy-plugin-channel-fake-bwrap
  )
  if(PLUGIN_SECURITY_HEADLESS_SANITIZERS)
    target_compile_options(omarchy-plugin-headless-slice-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-headless-slice-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-headless-slice-fake
    COMMAND omarchy-plugin-headless-slice-test fake
  )
  set_tests_properties(plugin-headless-slice-fake PROPERTIES
    TIMEOUT 30
    LABELS "integration;adversarial;headless;sandbox;broker;health"
  )
  add_test(NAME plugin-headless-slice-bwrap
    COMMAND omarchy-plugin-headless-slice-test bwrap
  )
  set_tests_properties(plugin-headless-slice-bwrap PROPERTIES
    TIMEOUT 30
    SKIP_RETURN_CODE 77
    LABELS "integration;adversarial;headless;sandbox;broker;health;linux"
  )
endif()
