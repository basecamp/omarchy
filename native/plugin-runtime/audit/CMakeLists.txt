cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_audit_store LANGUAGES CXX)

include(CTest)

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

if(PLUGIN_SECURITY_AUDIT_SANITIZERS)
  target_compile_options(omarchy-plugin-audit-store PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
  target_link_options(omarchy-plugin-audit-store PRIVATE -fsanitize=address,undefined)
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
endif()
