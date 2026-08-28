cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_render_session LANGUAGES CXX)

include(CTest)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)

if(NOT COMMAND omarchy_plugin_target_defaults)
  function(omarchy_plugin_target_defaults target)
    target_compile_features(${target} PUBLIC cxx_std_20)
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
  endfunction()
endif()

option(PLUGIN_SECURITY_RENDER_SESSION_SANITIZERS
  "Enable AddressSanitizer and UndefinedBehaviorSanitizer for D2" OFF)
function(omarchy_render_session_sanitize target)
  if(PLUGIN_SECURITY_RENDER_SESSION_SANITIZERS)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

if(NOT TARGET omarchy-plugin-wire)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire"
                   "${CMAKE_CURRENT_BINARY_DIR}/wire")
endif()
if(NOT TARGET omarchy-plugin-surface-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface"
                   "${CMAKE_CURRENT_BINARY_DIR}/surface")
endif()

add_library(omarchy-plugin-render-session STATIC render_session.cpp)
omarchy_plugin_target_defaults(omarchy-plugin-render-session)
omarchy_render_session_sanitize(omarchy-plugin-render-session)
target_include_directories(omarchy-plugin-render-session PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(omarchy-plugin-render-session PUBLIC
  omarchy-plugin-wire omarchy-plugin-surface-contract
)

if(BUILD_TESTING)
  if(NOT TARGET omarchy-plugin-trusted-bridge)
    add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../trusted-bridge"
                     "${CMAKE_CURRENT_BINARY_DIR}/trusted-bridge")
  endif()
  omarchy_render_session_sanitize(omarchy-plugin-trusted-bridge)

  add_library(omarchy-plugin-d2-worker-render STATIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../worker/worker_runtime.cpp"
  )
  omarchy_plugin_target_defaults(omarchy-plugin-d2-worker-render)
  omarchy_render_session_sanitize(omarchy-plugin-d2-worker-render)
  target_include_directories(omarchy-plugin-d2-worker-render PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/../worker"
  )
  target_link_libraries(omarchy-plugin-d2-worker-render PUBLIC
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick omarchy-plugin-surface-contract
  )

  add_executable(omarchy-plugin-render-session-test render_session_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-render-session-test)
  omarchy_render_session_sanitize(omarchy-plugin-render-session-test)
  target_compile_definitions(omarchy-plugin-render-session-test PRIVATE
    D2_WORKER_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../worker/fixtures"
  )
  target_link_libraries(omarchy-plugin-render-session-test PRIVATE
    omarchy-plugin-render-session omarchy-plugin-d2-worker-render
    omarchy-plugin-trusted-bridge Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  )
  add_test(NAME plugin-render-session COMMAND omarchy-plugin-render-session-test)
  set_tests_properties(plugin-render-session PROPERTIES
    TIMEOUT 30
    LABELS "integration;adversarial;render;qml;protocol"
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  )
endif()
