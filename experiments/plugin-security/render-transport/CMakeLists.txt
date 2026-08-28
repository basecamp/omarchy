cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_render_transport_spike LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(omarchy-plugin-render-spike
  main.cpp
)

target_link_libraries(omarchy-plugin-render-spike PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
)

install(TARGETS omarchy-plugin-render-spike RUNTIME DESTINATION bin)
