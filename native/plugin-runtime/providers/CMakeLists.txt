cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_providers LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-broker-core)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker")
endif()

add_library(omarchy-plugin-providers STATIC
  src/provider_set.cpp
  src/provider_schemas.cpp
)
target_compile_features(omarchy-plugin-providers PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-providers PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_include_directories(omarchy-plugin-providers PUBLIC include)
target_link_libraries(omarchy-plugin-providers PUBLIC
  omarchy-plugin-broker-core
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-providers-test tests/provider_set_test.cpp)
  target_compile_features(omarchy-plugin-providers-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-providers-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-providers-test PRIVATE
    omarchy-plugin-providers
  )
  add_test(NAME plugin-providers COMMAND omarchy-plugin-providers-test)
  set_tests_properties(plugin-providers PROPERTIES
    LABELS "unit;protocol;adversarial;providers"
  )

  add_executable(omarchy-plugin-provider-schema-test
    tests/provider_schema_test.cpp
  )
  target_compile_features(omarchy-plugin-provider-schema-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-schema-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-provider-schema-test PRIVATE
    omarchy-plugin-providers
  )
  add_test(NAME plugin-provider-schemas
    COMMAND omarchy-plugin-provider-schema-test
  )
  set_tests_properties(plugin-provider-schemas PROPERTIES
    LABELS "unit;protocol;adversarial;providers;golden"
  )
endif()
