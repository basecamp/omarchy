cmake_minimum_required(VERSION 3.21)

project(omarchy_plugin_wire_contract VERSION 0.1.0 LANGUAGES CXX)

include(CTest)

add_library(omarchy-plugin-wire STATIC
  src/common.cpp
  src/envelope.cpp
)

target_compile_features(omarchy-plugin-wire PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-wire PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(omarchy-plugin-wire PUBLIC include)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-wire-contract-test
    tests/wire_contract_test.cpp
  )
  target_compile_features(omarchy-plugin-wire-contract-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-wire-contract-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-wire-contract-test PRIVATE omarchy-plugin-wire)
  add_test(NAME plugin-wire-contract COMMAND omarchy-plugin-wire-contract-test)
  set_tests_properties(plugin-wire-contract PROPERTIES LABELS "unit;protocol;property")
endif()
