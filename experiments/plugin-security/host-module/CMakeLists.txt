cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_host_module_spike VERSION 0.1.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.8)

set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml")
set(host_module_directory "${QT_QML_OUTPUT_DIRECTORY}/Omarchy/PluginHost")
set(host_module_install_directory "${CMAKE_INSTALL_LIBDIR}/qt6/qml/Omarchy/PluginHost")

qt_add_qml_module(omarchy-plugin-host
  SHARED
  URI Omarchy.PluginHost
  VERSION 1.0
  PLUGIN_TARGET omarchy-plugin-host
  OUTPUT_DIRECTORY "${host_module_directory}"
  SOURCES
    HostFrameItem.cpp
    HostFrameItem.h
    HostProbeItem.cpp
    HostProbeItem.h
)

target_compile_features(omarchy-plugin-host PRIVATE cxx_std_20)
target_link_libraries(omarchy-plugin-host PRIVATE Qt6::Quick)

qt_add_executable(omarchy-plugin-host-smoke
  generic-host.cpp
)

target_compile_features(omarchy-plugin-host-smoke PRIVATE cxx_std_20)
target_link_libraries(omarchy-plugin-host-smoke PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
)

qt_add_executable(omarchy-plugin-frame-smoke
  frame-host.cpp
)

target_compile_features(omarchy-plugin-frame-smoke PRIVATE cxx_std_20)
target_link_libraries(omarchy-plugin-frame-smoke PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
)

install(TARGETS omarchy-plugin-host
  LIBRARY DESTINATION "${host_module_install_directory}"
)
install(FILES
  "${host_module_directory}/qmldir"
  "${host_module_directory}/omarchy-plugin-host.qmltypes"
  DESTINATION "${host_module_install_directory}"
)
install(TARGETS omarchy-plugin-host-smoke
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)
install(TARGETS omarchy-plugin-frame-smoke
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)

if(BUILD_TESTING)
  add_test(
    NAME external-host-module-import
    COMMAND omarchy-plugin-host-smoke "${QT_QML_OUTPUT_DIRECTORY}"
  )
  set_tests_properties(external-host-module-import PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QT_QUICK_BACKEND=software"
  )

  add_test(
    NAME fixed-memfd-frame-import
    COMMAND omarchy-plugin-frame-smoke "${QT_QML_OUTPUT_DIRECTORY}"
  )
  set_tests_properties(fixed-memfd-frame-import PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QT_QUICK_BACKEND=software"
  )
endif()
