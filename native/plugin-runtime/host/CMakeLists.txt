qt_add_executable(omarchy-plugin-host main.cpp)

omarchy_plugin_target_defaults(omarchy-plugin-host)
target_link_libraries(omarchy-plugin-host PRIVATE Qt6::Core Omarchy::PluginRuntimeVersion)

install(TARGETS omarchy-plugin-host RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")
