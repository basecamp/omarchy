cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_revision_store LANGUAGES CXX)
  include(CTest)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest-contract")
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../discovery"
                   "${CMAKE_CURRENT_BINARY_DIR}/discovery")
endif()

option(PLUGIN_SECURITY_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-revision-store STATIC revision_store.cpp)
target_include_directories(omarchy-plugin-revision-store PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(omarchy-plugin-revision-store PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-revision-store PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(omarchy-plugin-revision-store PUBLIC omarchy-plugin-discovery)

if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-revision-store PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(omarchy-plugin-revision-store PRIVATE -fsanitize=address,undefined)
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-revision-store-test revision_store_test.cpp)
  target_link_libraries(omarchy-plugin-revision-store-test PRIVATE omarchy-plugin-revision-store)
  target_compile_options(omarchy-plugin-revision-store-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-revision-store-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal"
    TREE_SHA256_GOLDEN="2f7b14d861677e84433b6178ddaaa4ad7e9bf1e7a44426c872b083f6f4fadd32"
  )
  if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
    target_compile_options(omarchy-plugin-revision-store-test PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(omarchy-plugin-revision-store-test PRIVATE -fsanitize=address,undefined)
  endif()
  add_test(NAME plugin-revision-store COMMAND omarchy-plugin-revision-store-test)
  set_tests_properties(plugin-revision-store PROPERTIES TIMEOUT 30 LABELS "unit;integration;adversarial")
endif()
