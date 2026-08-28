cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_broker_runtime LANGUAGES CXX)

include(CTest)

option(PLUGIN_SECURITY_BROKER_RUNTIME_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(NOT TARGET omarchy-plugin-providers)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../providers"
                   "${CMAKE_CURRENT_BINARY_DIR}/providers")
endif()
if(NOT TARGET omarchy-plugin-grant-store)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../grants"
                   "${CMAKE_CURRENT_BINARY_DIR}/grants")
endif()
if(NOT TARGET omarchy-plugin-audit-store)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../audit"
                   "${CMAKE_CURRENT_BINARY_DIR}/audit")
endif()

add_library(omarchy-plugin-broker-runtime STATIC broker_runtime.cpp)
target_include_directories(omarchy-plugin-broker-runtime PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-broker-runtime PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-broker-runtime PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-broker-runtime PUBLIC
  omarchy-plugin-providers
  omarchy-plugin-grant-store
  omarchy-plugin-audit-store
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
  add_executable(omarchy-plugin-broker-runtime-test broker_runtime_test.cpp)
  target_compile_features(omarchy-plugin-broker-runtime-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-broker-runtime-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-broker-runtime-test PRIVATE
    omarchy-plugin-broker-runtime
  )
  if(PLUGIN_SECURITY_BROKER_RUNTIME_SANITIZERS)
    target_compile_options(omarchy-plugin-broker-runtime-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-broker-runtime-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-broker-runtime COMMAND omarchy-plugin-broker-runtime-test)
  set_tests_properties(plugin-broker-runtime PROPERTIES
    TIMEOUT 30
    LABELS "unit;integration;adversarial;broker;audit"
  )
endif()
