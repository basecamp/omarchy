cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_broker_core LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()
if(NOT TARGET omarchy-plugin-permission-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permissions")
endif()

add_library(omarchy-plugin-broker-core STATIC
  src/broker_codec.cpp
  src/broker_schema.cpp
)
target_compile_features(omarchy-plugin-broker-core PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-broker-core PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_include_directories(omarchy-plugin-broker-core PUBLIC include)
target_link_libraries(omarchy-plugin-broker-core PUBLIC
  omarchy-plugin-wire
  omarchy-plugin-permission-contract
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-broker-core-test tests/broker_core_test.cpp)
  target_compile_features(omarchy-plugin-broker-core-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-broker-core-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-broker-core-test PRIVATE
    omarchy-plugin-broker-core
  )
  add_test(NAME plugin-broker-core COMMAND omarchy-plugin-broker-core-test)
  set_tests_properties(plugin-broker-core PROPERTIES
    LABELS "unit;protocol;adversarial;broker"
  )
endif()
