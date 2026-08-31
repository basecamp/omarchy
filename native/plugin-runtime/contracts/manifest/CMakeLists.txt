cmake_minimum_required(VERSION 3.20)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_manifest_contract LANGUAGES CXX)
endif()

include(CTest)

option(PLUGIN_SECURITY_ENABLE_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-manifest-contract STATIC src/manifest_contract.cpp)
target_include_directories(omarchy-plugin-manifest-contract PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../wire/include")
target_compile_features(omarchy-plugin-manifest-contract PUBLIC cxx_std_20)

target_compile_options(omarchy-plugin-manifest-contract PRIVATE -Wall -Wextra -Wpedantic -Werror)
if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-manifest-contract PRIVATE
    -fsanitize=address,undefined
    -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-manifest-contract PRIVATE -fsanitize=address,undefined)
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-manifest-contract-test tests/manifest_contract_test.cpp)
  target_link_libraries(omarchy-plugin-manifest-contract-test PRIVATE omarchy-plugin-manifest-contract)
  target_compile_definitions(omarchy-plugin-manifest-contract-test PRIVATE
    MANIFEST_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures"
    TREE_SHA256_GOLDEN="2f7b14d861677e84433b6178ddaaa4ad7e9bf1e7a44426c872b083f6f4fadd32"
    MANIFEST_SHA256_GOLDEN="1b224481ae39f93497ba4963ed494a54abe2db98e6a0899a28fb611c68a0d7d4"
    REQUEST_SHA256_GOLDEN="ca6c577e3501e4a134bcf59d69a4c5f50110f3e681bea81cb7f071ce785b51e1"
  )
  target_compile_options(omarchy-plugin-manifest-contract-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
    target_compile_options(omarchy-plugin-manifest-contract-test PRIVATE
      -fsanitize=address,undefined
      -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-manifest-contract-test PRIVATE -fsanitize=address,undefined)
  endif()

  add_test(NAME plugin-manifest-v2-contract COMMAND omarchy-plugin-manifest-contract-test)
  set_tests_properties(plugin-manifest-v2-contract PROPERTIES
    TIMEOUT 15
    LABELS "unit;protocol;adversarial;security"
  )
endif()
