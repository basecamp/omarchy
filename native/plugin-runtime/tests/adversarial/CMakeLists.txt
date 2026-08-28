cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_adversarial_harness LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()

add_executable(omarchy-plugin-malicious-worker malicious_worker.cpp)
target_compile_features(omarchy-plugin-malicious-worker PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-malicious-worker PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-malicious-worker PRIVATE
    -fsanitize=address,undefined
    -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-malicious-worker PRIVATE
    -fsanitize=address,undefined
  )
endif()

add_executable(omarchy-plugin-adversarial-harness-test
  adversarial_harness_test.cpp
)
target_compile_features(omarchy-plugin-adversarial-harness-test PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-adversarial-harness-test PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-adversarial-harness-test PRIVATE
    -fsanitize=address,undefined
    -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-adversarial-harness-test PRIVATE
    -fsanitize=address,undefined
  )
endif()
target_compile_definitions(omarchy-plugin-adversarial-harness-test PRIVATE
  MALICIOUS_WORKER_PATH="$<TARGET_FILE:omarchy-plugin-malicious-worker>"
)
target_link_libraries(omarchy-plugin-adversarial-harness-test PRIVATE
  omarchy-plugin-wire
)

add_test(NAME plugin-adversarial-harness
  COMMAND omarchy-plugin-adversarial-harness-test
)
set_tests_properties(plugin-adversarial-harness PROPERTIES
  LABELS "unit;integration;adversarial;fixtures;linux"
  TIMEOUT 15
)
