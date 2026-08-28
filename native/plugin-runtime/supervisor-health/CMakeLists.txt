cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_supervisor_health LANGUAGES CXX)
include(CTest)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  find_package(Qt6 REQUIRED COMPONENTS Core)
  function(omarchy_plugin_target_defaults target)
    target_compile_features(${target} PUBLIC cxx_std_20)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endfunction()
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/sandbox"
                   "${CMAKE_CURRENT_BINARY_DIR}/sandbox")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()

if(NOT TARGET omarchy-plugin-launcher)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../launcher"
                   "${CMAKE_CURRENT_BINARY_DIR}/launcher")
endif()
if(NOT TARGET omarchy-plugin-audit-store)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../audit"
                   "${CMAKE_CURRENT_BINARY_DIR}/audit")
endif()
if(NOT TARGET omarchy-plugin-surface-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface")
endif()

option(PLUGIN_SECURITY_HEALTH_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-supervisor-health STATIC supervisor_health.cpp)
target_include_directories(omarchy-plugin-supervisor-health PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-supervisor-health PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-supervisor-health PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-supervisor-health PUBLIC
  omarchy-plugin-launcher
  omarchy-plugin-audit-store
  omarchy-plugin-surface-contract
)
if(PLUGIN_SECURITY_HEALTH_SANITIZERS)
  target_compile_options(omarchy-plugin-supervisor-health PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-supervisor-health PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-supervisor-health-test supervisor_health_test.cpp)
  target_compile_features(omarchy-plugin-supervisor-health-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-supervisor-health-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-supervisor-health-test PRIVATE
    omarchy-plugin-supervisor-health
  )
  if(PLUGIN_SECURITY_HEALTH_SANITIZERS)
    target_compile_options(omarchy-plugin-supervisor-health-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-supervisor-health-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-supervisor-health COMMAND omarchy-plugin-supervisor-health-test)
  set_tests_properties(plugin-supervisor-health PROPERTIES
    TIMEOUT 30
    LABELS "unit;integration;adversarial;supervisor;health;audit"
  )
endif()
