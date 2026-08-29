cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_product_host LANGUAGES CXX)
include(CTest)

add_library(omarchy-plugin-product-host STATIC product_host.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-product-host)
target_include_directories(omarchy-plugin-product-host PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(omarchy-plugin-product-host PUBLIC
  Qt6::Core
  omarchy-plugin-discovery
  omarchy-plugin-grant-store
  omarchy-plugin-headless-slice
  omarchy-plugin-surface-host)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-product-host-test product_host_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-product-host-test)
  target_compile_definitions(omarchy-plugin-product-host-test PRIVATE
    PRODUCT_HOST_PET_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product/pet")
  target_link_libraries(omarchy-plugin-product-host-test PRIVATE
    omarchy-plugin-product-host
    omarchy-plugin-lifecycle)
  add_test(NAME plugin-product-host COMMAND omarchy-plugin-product-host-test)
  set_tests_properties(plugin-product-host PROPERTIES
    TIMEOUT 30
    LABELS "integration;security;discovery;grants;sandbox;qml")
endif()
