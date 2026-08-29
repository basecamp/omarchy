find_package(PkgConfig REQUIRED)
pkg_check_modules(WORKER_SECCOMP REQUIRED IMPORTED_TARGET libseccomp)

option(PLUGIN_SECURITY_WORKER_SANITIZERS
  "Enable AddressSanitizer and UndefinedBehaviorSanitizer for the QML worker" OFF)

set(OMARCHY_PLUGIN_EXTERNAL_FIXTURES "" CACHE STRING
  "Semicolon-separated schema-v2 plugin checkout paths for functional compatibility tests")

function(omarchy_plugin_worker_sanitize target)
  if(PLUGIN_SECURITY_WORKER_SANITIZERS)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

add_library(omarchy-plugin-worker-runtime STATIC
  worker_channel.cpp
  worker_runtime.cpp
  steady_seccomp.cpp
)
omarchy_plugin_target_defaults(omarchy-plugin-worker-runtime)
omarchy_plugin_worker_sanitize(omarchy-plugin-worker-runtime)
target_include_directories(omarchy-plugin-worker-runtime PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/sandbox/include"
)
target_link_libraries(omarchy-plugin-worker-runtime
  PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
         omarchy-plugin-wire omarchy-plugin-surface-contract
  PRIVATE omarchy-plugin-sandbox-policy PkgConfig::WORKER_SECCOMP
)

qt_add_executable(omarchy-plugin-qml-worker main.cpp)

qt_add_qml_module(omarchy-plugin-qml-worker
  URI Omarchy.PluginWorker
  VERSION 1.0
  RESOURCE_PREFIX /qt/qml
  QML_FILES Runtime.qml
)

omarchy_plugin_target_defaults(omarchy-plugin-qml-worker)
omarchy_plugin_worker_sanitize(omarchy-plugin-qml-worker)
target_link_libraries(omarchy-plugin-qml-worker
  PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Omarchy::PluginRuntimeVersion
          omarchy-plugin-worker-runtime
)

install(TARGETS omarchy-plugin-qml-worker RUNTIME DESTINATION "${CMAKE_INSTALL_LIBDIR}/omarchy/plugin-runtime")

if(BUILD_TESTING)
  add_executable(omarchy-plugin-external-fixture-test external_fixture_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-external-fixture-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-external-fixture-test)
  target_link_libraries(omarchy-plugin-external-fixture-test PRIVATE
    omarchy-plugin-worker-runtime
  )

  foreach(external_fixture IN LISTS OMARCHY_PLUGIN_EXTERNAL_FIXTURES)
    if(NOT IS_ABSOLUTE "${external_fixture}")
      message(FATAL_ERROR "External plugin fixture must be an absolute path: ${external_fixture}")
    endif()
    string(SHA256 external_fixture_hash "${external_fixture}")
    string(SUBSTRING "${external_fixture_hash}" 0 12 external_fixture_id)
    add_test(NAME "plugin-external-fixture-${external_fixture_id}"
      COMMAND omarchy-plugin-external-fixture-test
        --root "${external_fixture}" --function stepForTest)
    set_tests_properties("plugin-external-fixture-${external_fixture_id}" PROPERTIES
      LABELS "integration;render;external-fixture"
      TIMEOUT 30
      ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
    )
  endforeach()

  add_executable(omarchy-plugin-worker-runtime-test worker_runtime_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-worker-runtime-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-worker-runtime-test)
  target_link_libraries(omarchy-plugin-worker-runtime-test PRIVATE
    omarchy-plugin-worker-runtime
  )
  target_compile_definitions(omarchy-plugin-worker-runtime-test PRIVATE
    WORKER_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
  )
  add_test(NAME plugin-worker-runtime COMMAND omarchy-plugin-worker-runtime-test)
  set_tests_properties(plugin-worker-runtime PROPERTIES
    LABELS "unit;integration;adversarial;render"
    TIMEOUT 30
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  )

  add_executable(omarchy-plugin-worker-channel-test worker_channel_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-worker-channel-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-worker-channel-test)
  target_link_libraries(omarchy-plugin-worker-channel-test PRIVATE
    omarchy-plugin-worker-runtime
  )
  add_test(NAME plugin-worker-channel COMMAND omarchy-plugin-worker-channel-test)
  set_tests_properties(plugin-worker-channel PROPERTIES
    LABELS "unit;protocol;adversarial"
    TIMEOUT 20
  )
endif()
