cmake_minimum_required(VERSION 3.24)
project(omarchy_plugin_expressive_surface LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_EXPRESSIVE_SURFACE_SANITIZERS "Enable ASan/UBSan" OFF)
if(PLUGIN_SECURITY_EXPRESSIVE_SURFACE_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
function(expressive_defaults target)
  target_compile_features(${target} PRIVATE cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

if(NOT TARGET omarchy-plugin-surface-host)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../surface-host"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface-host")
endif()

add_library(omarchy-plugin-expressive-surface STATIC expressive_surface.cpp)
expressive_defaults(omarchy-plugin-expressive-surface)
target_include_directories(omarchy-plugin-expressive-surface PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(omarchy-plugin-expressive-surface PUBLIC
  omarchy-plugin-surface-host)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-expressive-surface-test expressive_surface_test.cpp)
  expressive_defaults(omarchy-plugin-expressive-surface-test)
  target_compile_definitions(omarchy-plugin-expressive-surface-test PRIVATE
    E2_PET_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product/pet")
  target_link_libraries(omarchy-plugin-expressive-surface-test PRIVATE
    omarchy-plugin-expressive-surface omarchy-plugin-d2-worker-render)
  add_test(NAME plugin-expressive-surface COMMAND omarchy-plugin-expressive-surface-test)
  set_tests_properties(plugin-expressive-surface PROPERTIES
    TIMEOUT 30
    LABELS "vertical;integration;adversarial;render;qml;input;security"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")
endif()
