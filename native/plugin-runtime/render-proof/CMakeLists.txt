cmake_minimum_required(VERSION 3.24)
project(omarchy_plugin_render_proof LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_RENDER_PROOF_SANITIZERS "Enable ASan/UBSan" OFF)
if(PLUGIN_SECURITY_RENDER_PROOF_SANITIZERS)
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
set(CMAKE_AUTOMOC ON)

if(NOT TARGET omarchy-plugin-expressive-surface)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../expressive-surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/expressive-surface")
endif()
if(NOT TARGET omarchy-plugin-embedded-bar-test)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../vertical-slices/embedded-bar"
                   "${CMAKE_CURRENT_BINARY_DIR}/embedded-bar")
endif()

add_executable(omarchy-plugin-render-proof-test render_proof_test.cpp)
target_compile_features(omarchy-plugin-render-proof-test PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-render-proof-test PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_compile_definitions(omarchy-plugin-render-proof-test PRIVATE
  F2_POMODORO_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product/pomodoro"
  F2_PET_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../fixtures/product/pet"
  F2_ARTIFACT_DIR="${CMAKE_CURRENT_BINARY_DIR}/artifacts")
target_link_libraries(omarchy-plugin-render-proof-test PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-d2-worker-render
  omarchy-plugin-expressive-surface
  omarchy-plugin-manifest-contract)

add_test(NAME plugin-render-fidelity-proof COMMAND omarchy-plugin-render-proof-test)
set_tests_properties(plugin-render-fidelity-proof PROPERTIES
  TIMEOUT 60
  LABELS "proof;vertical;integration;adversarial;render;qml;input;performance;visual"
  ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0")
