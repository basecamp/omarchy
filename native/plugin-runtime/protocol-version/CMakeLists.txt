add_library(omarchy-plugin-runtime-version STATIC Version.cpp)
add_library(Omarchy::PluginRuntimeVersion ALIAS omarchy-plugin-runtime-version)

omarchy_plugin_target_defaults(omarchy-plugin-runtime-version)
set_target_properties(omarchy-plugin-runtime-version PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(omarchy-plugin-runtime-version
  PUBLIC "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>"
  PRIVATE "${CMAKE_BINARY_DIR}/generated"
)
