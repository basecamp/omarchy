find_package(PkgConfig REQUIRED)
pkg_check_modules(SECCOMP REQUIRED IMPORTED_TARGET libseccomp)
pkg_check_modules(SYSTEMD REQUIRED IMPORTED_TARGET libsystemd)

add_library(omarchy-plugin-launcher STATIC
  src/bus_connection.cpp
  src/launcher.cpp
  src/process_cleanup.cpp
  src/systemd_resource_scope.cpp
)
add_library(Omarchy::PluginLauncher ALIAS omarchy-plugin-launcher)
omarchy_plugin_target_defaults(omarchy-plugin-launcher)
target_include_directories(omarchy-plugin-launcher PUBLIC include)
target_link_libraries(omarchy-plugin-launcher
  PUBLIC Omarchy::PluginSandboxPolicy
  PRIVATE Qt6::Core PkgConfig::SECCOMP PkgConfig::SYSTEMD
)

if(BUILD_TESTING)
  add_library(omarchy-plugin-launcher-test-support STATIC
    tests/support/src/test_supervisor.cpp)
  add_library(Omarchy::PluginLauncherTestSupport ALIAS
    omarchy-plugin-launcher-test-support)
  omarchy_plugin_target_defaults(omarchy-plugin-launcher-test-support)
  target_include_directories(omarchy-plugin-launcher-test-support
    PUBLIC tests/support/include
    PRIVATE src)
  target_link_libraries(omarchy-plugin-launcher-test-support PUBLIC
    Omarchy::PluginLauncher
    Omarchy::PluginSandboxTestSupport)
endif()
