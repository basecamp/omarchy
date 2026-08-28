cmake_minimum_required(VERSION 3.21)

project(omarchy_plugin_native_build_probe VERSION 0.1.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(omarchy-plugin-native-build-probe
  main.cpp
)

qt_add_qml_module(omarchy-plugin-native-build-probe
  URI Omarchy.PluginSecurity.NativeBuild
  VERSION 1.0
  QML_FILES
    Main.qml
)

target_compile_features(omarchy-plugin-native-build-probe PRIVATE cxx_std_20)

target_link_libraries(omarchy-plugin-native-build-probe PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
)

install(TARGETS omarchy-plugin-native-build-probe
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)

if(BUILD_TESTING)
  add_test(
    NAME native-build-probe
    COMMAND omarchy-plugin-native-build-probe
  )
  set_tests_properties(native-build-probe PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=;QT_QUICK_BACKEND=software"
  )
endif()
