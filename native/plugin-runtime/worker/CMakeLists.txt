find_package(PkgConfig REQUIRED)
pkg_check_modules(WORKER_SECCOMP REQUIRED IMPORTED_TARGET libseccomp)

option(PLUGIN_SECURITY_WORKER_SANITIZERS
  "Enable AddressSanitizer and UndefinedBehaviorSanitizer for the QML worker" OFF)

set(OMARCHY_PLUGIN_EXTERNAL_FIXTURES "" CACHE STRING
  "Semicolon-separated schema-v2 plugin checkout paths for functional integration tests")
set(OMARCHY_PLUGIN_EXTERNAL_DEFINITIONS "" CACHE PATH
  "Independent trusted capability-definition directory for external fixtures")
set(OMARCHY_PLUGIN_EXTERNAL_ADAPTERS "" CACHE STRING
  "Semicolon-separated adapter-class:digest:abi registrations for external fixtures")

function(omarchy_plugin_worker_sanitize target)
  if(PLUGIN_SECURITY_WORKER_SANITIZERS)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

add_library(omarchy-plugin-worker-runtime STATIC
  src/qml_broker_api.cpp
  src/sidecar_supervisor.cpp
  src/worker_channel.cpp
  src/worker_runtime.cpp
  src/steady_seccomp.cpp
)
omarchy_plugin_target_defaults(omarchy-plugin-worker-runtime)
omarchy_plugin_worker_sanitize(omarchy-plugin-worker-runtime)
target_include_directories(omarchy-plugin-worker-runtime PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/wire/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/surface/include"
  "${CMAKE_CURRENT_SOURCE_DIR}/../contracts/sandbox/include"
)
target_link_libraries(omarchy-plugin-worker-runtime
  PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
         omarchy-plugin-wire omarchy-plugin-surface-contract
         omarchy-plugin-broker-core omarchy-plugin-capability-definitions
  PRIVATE omarchy-plugin-sandbox-policy omarchy-plugin-manifest-contract
          PkgConfig::WORKER_SECCOMP
)

qt_add_executable(omarchy-plugin-qml-worker src/main.cpp)

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

install(TARGETS omarchy-plugin-qml-worker RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")

if(BUILD_TESTING)
  add_executable(omarchy-plugin-sidecar-probe src/sidecar_probe.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sidecar-probe)
  add_executable(omarchy-plugin-sidecar-supervisor-test
    tests/sidecar_supervisor_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sidecar-supervisor-test)
  target_link_libraries(omarchy-plugin-sidecar-supervisor-test PRIVATE
    omarchy-plugin-worker-runtime)
  target_compile_definitions(omarchy-plugin-sidecar-supervisor-test PRIVATE
    SIDECAR_PROBE_PATH="$<TARGET_FILE:omarchy-plugin-sidecar-probe>")
  add_dependencies(omarchy-plugin-sidecar-supervisor-test
    omarchy-plugin-sidecar-probe)
  add_test(NAME plugin-sidecar-supervisor
    COMMAND omarchy-plugin-sidecar-supervisor-test)
  set_tests_properties(plugin-sidecar-supervisor PROPERTIES
    LABELS "unit;integration;sandbox;security" TIMEOUT 10)
  add_test(NAME plugin-sidecar-real-bwrap
    COMMAND /usr/bin/bwrap
      --unshare-user --unshare-pid --unshare-ipc --unshare-uts --unshare-net
      --disable-userns --assert-userns-disabled
      --uid 0 --gid 0 --as-pid-1 --cap-drop ALL --clearenv
      --setenv PATH /runtime --setenv HOME /home/plugin --setenv PWD /plugin
      --proc /proc --dev /dev --dir /usr
      --ro-bind /usr/lib /usr/lib --symlink usr/lib /lib --symlink usr/lib /lib64
      --dir /runtime
      --ro-bind $<TARGET_FILE:omarchy-plugin-sidecar-supervisor-test> /runtime/test
      --dir /plugin --dir /plugin/bin
      --ro-bind $<TARGET_FILE:omarchy-plugin-sidecar-probe> /plugin/bin/probe
      --tmpfs /tmp --tmpfs /run --dir /home --dir /home/plugin
      --chdir /plugin -- /runtime/test --inside-bwrap)
  set_tests_properties(plugin-sidecar-real-bwrap PROPERTIES
    LABELS "integration;sandbox;security;real-bwrap" TIMEOUT 10)

  add_executable(omarchy-plugin-external-fixture-test tests/external_fixture_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-external-fixture-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-external-fixture-test)
  target_link_libraries(omarchy-plugin-external-fixture-test PRIVATE
    omarchy-plugin-worker-runtime omarchy-plugin-capability-definitions
  )

  if(OMARCHY_PLUGIN_EXTERNAL_FIXTURES AND
     (NOT IS_ABSOLUTE "${OMARCHY_PLUGIN_EXTERNAL_DEFINITIONS}" OR
      NOT OMARCHY_PLUGIN_EXTERNAL_ADAPTERS))
    message(FATAL_ERROR
      "External fixtures require an absolute independent definition directory and explicit adapter registrations")
  endif()
  foreach(external_fixture IN LISTS OMARCHY_PLUGIN_EXTERNAL_FIXTURES)
    if(NOT IS_ABSOLUTE "${external_fixture}")
      message(FATAL_ERROR "External plugin fixture must be an absolute path: ${external_fixture}")
    endif()
    string(SHA256 external_fixture_hash "${external_fixture}")
    string(SUBSTRING "${external_fixture_hash}" 0 12 external_fixture_id)
    add_test(NAME "plugin-external-fixture-${external_fixture_id}"
      COMMAND omarchy-plugin-external-fixture-test
        --root "${external_fixture}"
        --definitions "${OMARCHY_PLUGIN_EXTERNAL_DEFINITIONS}"
        --adapters "${OMARCHY_PLUGIN_EXTERNAL_ADAPTERS}")
    set_tests_properties("plugin-external-fixture-${external_fixture_id}" PROPERTIES
      LABELS "integration;render;external-fixture"
      TIMEOUT 30
      ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
    )
  endforeach()

  add_executable(omarchy-plugin-worker-runtime-test tests/worker_runtime_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-worker-runtime-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-worker-runtime-test)
  target_link_libraries(omarchy-plugin-worker-runtime-test PRIVATE
    omarchy-plugin-worker-runtime
  )
  target_compile_definitions(omarchy-plugin-worker-runtime-test PRIVATE
    WORKER_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures"
  )
  add_test(NAME plugin-worker-runtime COMMAND omarchy-plugin-worker-runtime-test)
  set_tests_properties(plugin-worker-runtime PROPERTIES
    LABELS "unit;integration;adversarial;render"
    TIMEOUT 30
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  )

  add_executable(omarchy-plugin-worker-channel-test tests/worker_channel_test.cpp)
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

  add_executable(omarchy-plugin-qml-broker-api-test tests/qml_broker_api_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-qml-broker-api-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-qml-broker-api-test)
  target_link_libraries(omarchy-plugin-qml-broker-api-test PRIVATE
    omarchy-plugin-worker-runtime)
  add_test(NAME plugin-qml-broker-api COMMAND omarchy-plugin-qml-broker-api-test)
  set_tests_properties(plugin-qml-broker-api PROPERTIES
    LABELS "unit;integration;protocol;broker;qml;security"
    TIMEOUT 20
    SKIP_RETURN_CODE 77
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software")
endif()
