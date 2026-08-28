cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_lifecycle LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-manifest-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest-contract")
endif()
if(NOT TARGET omarchy-plugin-discovery)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../discovery"
                   "${CMAKE_CURRENT_BINARY_DIR}/discovery")
endif()
if(NOT TARGET omarchy-plugin-revision-store)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../revision-store"
                   "${CMAKE_CURRENT_BINARY_DIR}/revision-store")
endif()
if(NOT TARGET omarchy-plugin-grant-store)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../grants"
                   "${CMAKE_CURRENT_BINARY_DIR}/grants")
endif()

add_library(omarchy-plugin-lifecycle STATIC lifecycle.cpp)
target_include_directories(omarchy-plugin-lifecycle PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-lifecycle PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-lifecycle PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-lifecycle PUBLIC
  omarchy-plugin-revision-store
  omarchy-plugin-grant-store
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-lifecycle-test lifecycle_test.cpp)
  target_compile_features(omarchy-plugin-lifecycle-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-lifecycle-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_compile_definitions(omarchy-plugin-lifecycle-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal"
  )
  target_link_libraries(omarchy-plugin-lifecycle-test PRIVATE
    omarchy-plugin-lifecycle
  )
  add_test(NAME plugin-lifecycle COMMAND omarchy-plugin-lifecycle-test)
  set_tests_properties(plugin-lifecycle PROPERTIES
    TIMEOUT 30
    LABELS "unit;integration;adversarial;lifecycle"
  )
endif()
