cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_broker_runtime LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_BROKER_RUNTIME_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(NOT TARGET omarchy-plugin-providers)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../providers"
                   "${CMAKE_CURRENT_BINARY_DIR}/providers")
endif()
add_library(omarchy-plugin-broker-runtime STATIC
  src/broker_runtime.cpp
  src/dynamic_broker_runtime.cpp
  src/gesture_eligibility.cpp
  ../audit/src/audit_store.cpp
)
target_include_directories(omarchy-plugin-broker-runtime PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../audit/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../policy/src"
)
target_compile_features(omarchy-plugin-broker-runtime PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-broker-runtime PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-broker-runtime PUBLIC
  omarchy-plugin-providers
  omarchy-plugin-permission-contract
)
if(PLUGIN_SECURITY_BROKER_RUNTIME_SANITIZERS)
  target_compile_options(omarchy-plugin-broker-runtime PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-broker-runtime PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  find_package(Threads REQUIRED)
  add_executable(omarchy-plugin-audit-store-test
    ../audit/tests/audit_store_test.cpp)
  target_compile_features(omarchy-plugin-audit-store-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-audit-store-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-audit-store-test PRIVATE
    omarchy-plugin-broker-runtime)
  add_test(NAME plugin-audit-store COMMAND omarchy-plugin-audit-store-test)
  set_tests_properties(plugin-audit-store PROPERTIES
    TIMEOUT 30 LABELS "unit;integration;adversarial;audit;security")

  add_executable(omarchy-plugin-dynamic-broker-runtime-test
    tests/dynamic_broker_runtime_test.cpp)
  target_compile_features(omarchy-plugin-dynamic-broker-runtime-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-dynamic-broker-runtime-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-dynamic-broker-runtime-test PRIVATE
    omarchy-plugin-broker-runtime)
  add_test(NAME plugin-dynamic-broker-runtime
    COMMAND omarchy-plugin-dynamic-broker-runtime-test)
  set_tests_properties(plugin-dynamic-broker-runtime PROPERTIES
    LABELS "security")

  add_executable(omarchy-plugin-gesture-eligibility-test
    tests/gesture_eligibility_test.cpp)
  target_compile_features(omarchy-plugin-gesture-eligibility-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-gesture-eligibility-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-gesture-eligibility-test PRIVATE
    omarchy-plugin-broker-runtime Threads::Threads)
  add_test(NAME plugin-gesture-eligibility
    COMMAND omarchy-plugin-gesture-eligibility-test)
  set_tests_properties(plugin-gesture-eligibility PROPERTIES
    TIMEOUT 10 LABELS "unit;security;gesture;adversarial")
endif()
