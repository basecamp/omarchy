cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_adversarial_harness LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

find_package(Qt6 REQUIRED COMPONENTS Core)

function(omarchy_plugin_target_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()
if(NOT TARGET omarchy-plugin-sandbox-policy)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../contracts/sandbox"
                   "${CMAKE_CURRENT_BINARY_DIR}/sandbox")
endif()
if(NOT TARGET omarchy-plugin-launcher)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../launcher"
                   "${CMAKE_CURRENT_BINARY_DIR}/launcher")
endif()

if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  # Instrument every trusted dependency in the C11 path. The B5 sandbox probe
  # itself remains uninstrumented because its exact environment intentionally
  # cannot carry ASAN_OPTIONS and its seccomp policy denies LeakSanitizer's
  # helper process; the C11 malicious worker is instrumented separately below.
  foreach(dependency_target IN ITEMS
      omarchy-plugin-wire
      omarchy-plugin-wire-contract-test
      omarchy-plugin-sandbox-policy
      omarchy-plugin-sandbox-policy-test
      omarchy-plugin-sandbox-enforcement-test
      omarchy-plugin-launcher)
    if(TARGET ${dependency_target})
      target_compile_options(${dependency_target} PRIVATE
        -fsanitize=address,undefined
        -fno-omit-frame-pointer
      )
      target_link_options(${dependency_target} PRIVATE
        -fsanitize=address,undefined
      )
    endif()
  endforeach()
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
  Omarchy::PluginLauncher
)
add_dependencies(omarchy-plugin-adversarial-harness-test
  omarchy-plugin-malicious-worker
)

add_test(NAME plugin-adversarial-harness
  COMMAND omarchy-plugin-adversarial-harness-test
)
set_tests_properties(plugin-adversarial-harness PROPERTIES
  LABELS "unit;integration;adversarial;fixtures;linux"
  TIMEOUT 15
)
