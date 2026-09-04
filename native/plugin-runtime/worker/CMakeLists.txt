find_package(PkgConfig REQUIRED)
# Qt has no public API for injecting a complete touch frame into a window.
# Keep the exact-version QPA dependency inside the worker adapter target.
find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)
pkg_check_modules(WORKER_SECCOMP REQUIRED IMPORTED_TARGET libseccomp)

option(PLUGIN_SECURITY_WORKER_SANITIZERS
  "Enable AddressSanitizer and UndefinedBehaviorSanitizer for the QML worker" OFF)

function(omarchy_plugin_worker_sanitize target)
  if(PLUGIN_SECURITY_WORKER_SANITIZERS)
    target_compile_options(${target} PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endif()
endfunction()

add_library(omarchy-plugin-worker-runtime STATIC
  src/plugin_source_policy.cpp
  src/qt_touch_injector.cpp
  src/qml_broker_api.cpp
  src/sidecar_supervisor.cpp
  src/worker_channel.cpp
  src/worker_runtime.cpp
  src/steady_seccomp.cpp
)
qt_add_resources(omarchy-plugin-worker-runtime plugin_presentation_qml
  PREFIX "/qt/qml/Omarchy/PluginPresentation"
  BASE "${CMAKE_CURRENT_SOURCE_DIR}/../presentation/qml"
  FILES
    ../presentation/qml/qmldir
    ../presentation/qml/BarWidget.qml
    ../presentation/qml/Border.qml
    ../presentation/qml/BorderSurface.qml
    ../presentation/qml/BrokerProcess.qml
    ../presentation/qml/Button.qml
    ../presentation/qml/ConfirmDialog.qml
    ../presentation/qml/Color.qml
    ../presentation/qml/CursorSurface.qml
    ../presentation/qml/Dropdown.qml
    ../presentation/qml/KeyboardPanel.qml
    ../presentation/qml/PackagedText.qml
    ../presentation/qml/Panel.qml
    ../presentation/qml/PanelActionButton.qml
    ../presentation/qml/PanelHero.qml
    ../presentation/qml/PanelKeyCatcher.qml
    ../presentation/qml/PanelSectionHeader.qml
    ../presentation/qml/PanelSeparator.qml
    ../presentation/qml/PanelSlider.qml
    ../presentation/qml/PrivateStorage.qml
    ../presentation/qml/StdioCollector.qml
    ../presentation/qml/Style.qml
    ../presentation/qml/TextField.qml
    ../presentation/qml/ToolTip.qml
    ../presentation/qml/Toggle.qml
    ../presentation/qml/ToggleSwitch.qml
    ../presentation/qml/Util.qml
    ../presentation/qml/WidgetButton.qml)
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
  PRIVATE Qt6::GuiPrivate
          omarchy-plugin-sandbox-policy omarchy-plugin-manifest-contract
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
          Omarchy::PluginRuntimePaths
          omarchy-plugin-worker-runtime
)

install(TARGETS omarchy-plugin-qml-worker RUNTIME DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/bin")

if(BUILD_TESTING)
  add_executable(omarchy-plugin-sidecar-probe src/sidecar_probe.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sidecar-probe)
  add_executable(omarchy-plugin-sidecar-supervisor-test
    tests/sidecar_supervisor_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-sidecar-supervisor-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-sidecar-supervisor-test)
  target_link_libraries(omarchy-plugin-sidecar-supervisor-test PRIVATE
    omarchy-plugin-worker-runtime)
  add_dependencies(omarchy-plugin-sidecar-supervisor-test
    omarchy-plugin-sidecar-probe)
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
    LABELS "unit;integration;adversarial;render;security"
    TIMEOUT 30
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QT_QUICK_CONTROLS_STYLE=Basic;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  )
  add_test(NAME plugin-worker-runtime-sibling-focus
    COMMAND omarchy-plugin-worker-runtime-test --sibling-focus-only)
  add_test(NAME plugin-worker-runtime-sibling-grab
    COMMAND omarchy-plugin-worker-runtime-test --sibling-grab-only)
  set_tests_properties(
    plugin-worker-runtime-sibling-focus
    plugin-worker-runtime-sibling-grab
    PROPERTIES
      LABELS "unit;integration;render;input"
      TIMEOUT 20
      ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QT_QUICK_CONTROLS_STYLE=Basic;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  )

  add_executable(omarchy-plugin-worker-channel-test tests/worker_channel_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-worker-channel-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-worker-channel-test)
  target_link_libraries(omarchy-plugin-worker-channel-test PRIVATE
    omarchy-plugin-worker-runtime
  )
  add_test(NAME plugin-worker-channel COMMAND omarchy-plugin-worker-channel-test)
  set_tests_properties(plugin-worker-channel PROPERTIES
    LABELS "unit;protocol;adversarial;security"
    TIMEOUT 20
  )

  add_executable(omarchy-plugin-qml-broker-api-test tests/qml_broker_api_test.cpp)
  omarchy_plugin_target_defaults(omarchy-plugin-qml-broker-api-test)
  omarchy_plugin_worker_sanitize(omarchy-plugin-qml-broker-api-test)
  target_compile_definitions(omarchy-plugin-qml-broker-api-test PRIVATE
    OMARCHY_NEUTRAL_SURFACE_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures/neutral-surfaces"
  )
  target_link_libraries(omarchy-plugin-qml-broker-api-test PRIVATE
    omarchy-plugin-worker-runtime)
  add_test(NAME plugin-qml-broker-api COMMAND omarchy-plugin-qml-broker-api-test)
  set_tests_properties(plugin-qml-broker-api PROPERTIES
    LABELS "unit;integration;protocol;broker;qml;security"
    TIMEOUT 20
    SKIP_RETURN_CODE 77
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QT_QUICK_CONTROLS_STYLE=Basic;QSG_RHI_BACKEND=software")
endif()
