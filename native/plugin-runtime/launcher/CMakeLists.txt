find_package(PkgConfig REQUIRED)
pkg_check_modules(SECCOMP REQUIRED IMPORTED_TARGET libseccomp)
pkg_check_modules(SYSTEMD REQUIRED IMPORTED_TARGET libsystemd)

add_library(omarchy-plugin-launcher STATIC src/launcher.cpp)
add_library(Omarchy::PluginLauncher ALIAS omarchy-plugin-launcher)
omarchy_plugin_target_defaults(omarchy-plugin-launcher)
target_include_directories(omarchy-plugin-launcher PUBLIC include)
target_link_libraries(omarchy-plugin-launcher
  PUBLIC Omarchy::PluginSandboxPolicy
  PRIVATE Qt6::Core PkgConfig::SECCOMP PkgConfig::SYSTEMD
)

if(TARGET omarchy-plugin-host)
  target_link_libraries(omarchy-plugin-host PRIVATE Omarchy::PluginLauncher)
endif()
