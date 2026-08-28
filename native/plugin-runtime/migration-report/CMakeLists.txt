cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_migration_report LANGUAGES CXX)

include(CTest)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core)

option(PLUGIN_SECURITY_MIGRATION_REPORT_SANITIZERS
       "Enable migration report AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

set(CMAKE_AUTOMOC ON)

if(NOT TARGET omarchy-plugin-manifest-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest")
endif()

add_library(omarchy-plugin-migration-report STATIC
  migration_report.cpp
)
target_compile_features(omarchy-plugin-migration-report PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-migration-report PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_include_directories(omarchy-plugin-migration-report PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(omarchy-plugin-migration-report PUBLIC
  Qt6::Core
  omarchy-plugin-manifest-contract
)
if(PLUGIN_SECURITY_MIGRATION_REPORT_SANITIZERS)
  target_compile_options(omarchy-plugin-migration-report PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-migration-report PRIVATE
    -fsanitize=address,undefined
  )
endif()

add_executable(omarchy-plugin-migration-report-cli cli.cpp)
target_compile_features(omarchy-plugin-migration-report-cli PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-migration-report-cli PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-migration-report-cli PRIVATE
  omarchy-plugin-migration-report
)
if(PLUGIN_SECURITY_MIGRATION_REPORT_SANITIZERS)
  target_compile_options(omarchy-plugin-migration-report-cli PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-migration-report-cli PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-migration-report-test migration_report_test.cpp)
  target_compile_features(omarchy-plugin-migration-report-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-migration-report-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_compile_definitions(omarchy-plugin-migration-report-test PRIVATE
    MIGRATION_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
    PRODUCT_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product"
    OMARCHY_SOURCE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../../.."
  )
  target_link_libraries(omarchy-plugin-migration-report-test PRIVATE
    omarchy-plugin-migration-report
  )
  if(PLUGIN_SECURITY_MIGRATION_REPORT_SANITIZERS)
    target_compile_options(omarchy-plugin-migration-report-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-migration-report-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-migration-report
    COMMAND omarchy-plugin-migration-report-test
  )
  set_tests_properties(plugin-migration-report PROPERTIES
    LABELS "unit;integration;migration;adversarial"
    TIMEOUT 20
  )
endif()
