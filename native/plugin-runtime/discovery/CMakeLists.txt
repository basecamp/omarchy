cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_discovery LANGUAGES CXX)
  include(CTest)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest-contract")
endif()

option(PLUGIN_SECURITY_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-discovery STATIC discovery.cpp)
target_include_directories(omarchy-plugin-discovery PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(omarchy-plugin-discovery PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-discovery PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(omarchy-plugin-discovery PUBLIC omarchy-plugin-manifest-contract)

if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-discovery PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(omarchy-plugin-discovery PRIVATE -fsanitize=address,undefined)
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-discovery-test discovery_test.cpp)
  target_link_libraries(omarchy-plugin-discovery-test PRIVATE omarchy-plugin-discovery)
  target_compile_options(omarchy-plugin-discovery-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_compile_definitions(omarchy-plugin-discovery-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal"
    MANIFEST_DUPLICATE_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/invalid-duplicate"
    DISCOVERY_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
    TREE_SHA256_GOLDEN="2f7b14d861677e84433b6178ddaaa4ad7e9bf1e7a44426c872b083f6f4fadd32"
  )
  if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
    target_compile_options(omarchy-plugin-discovery-test PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(omarchy-plugin-discovery-test PRIVATE -fsanitize=address,undefined)
  endif()
  add_test(NAME plugin-manifest-discovery COMMAND omarchy-plugin-discovery-test)
  set_tests_properties(plugin-manifest-discovery PROPERTIES TIMEOUT 20 LABELS "unit;integration;adversarial")
endif()
