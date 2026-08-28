cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_audit_store LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

if(NOT TARGET omarchy-plugin-permission-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permissions")
endif()

option(PLUGIN_SECURITY_AUDIT_SANITIZERS "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-audit-store STATIC audit_store.cpp)
target_include_directories(omarchy-plugin-audit-store PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(omarchy-plugin-audit-store PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-audit-store PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(omarchy-plugin-audit-store PUBLIC omarchy-plugin-permission-contract)

add_executable(omarchy-plugin-audit-store-cli audit_store_cli.cpp)
set_target_properties(omarchy-plugin-audit-store-cli PROPERTIES
  OUTPUT_NAME omarchy-plugin-audit-store
)
target_link_libraries(omarchy-plugin-audit-store-cli PRIVATE omarchy-plugin-audit-store)
target_compile_features(omarchy-plugin-audit-store-cli PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-audit-store-cli PRIVATE -Wall -Wextra -Wpedantic -Werror)

install(TARGETS omarchy-plugin-audit-store-cli
        RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")

if(PLUGIN_SECURITY_AUDIT_SANITIZERS)
  foreach(target IN ITEMS omarchy-plugin-audit-store omarchy-plugin-audit-store-cli)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endforeach()
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-audit-store-test audit_store_test.cpp)
  target_link_libraries(omarchy-plugin-audit-store-test PRIVATE omarchy-plugin-audit-store)
  target_compile_options(omarchy-plugin-audit-store-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  if(PLUGIN_SECURITY_AUDIT_SANITIZERS)
    target_compile_options(omarchy-plugin-audit-store-test PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(omarchy-plugin-audit-store-test PRIVATE -fsanitize=address,undefined)
  endif()
  add_test(NAME plugin-audit-store COMMAND omarchy-plugin-audit-store-test)
  set_tests_properties(plugin-audit-store PROPERTIES TIMEOUT 30 LABELS "unit;integration;adversarial;audit")
  add_test(NAME plugin-audit-store-cli-help
           COMMAND omarchy-plugin-audit-store-cli --help)
  set_tests_properties(plugin-audit-store-cli-help PROPERTIES
    TIMEOUT 10
    PASS_REGULAR_EXPRESSION "trusted, redacted plugin security events"
    LABELS "integration;cli;audit"
  )
endif()
