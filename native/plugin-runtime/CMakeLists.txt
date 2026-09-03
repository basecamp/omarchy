cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_runtime VERSION 0.1.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

set(OMARCHY_PLUGIN_QT_MIN_VERSION "" CACHE STRING "Optional minimum Qt 6 version required by the package build")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Install path prefix" FORCE)
endif()
if(NOT CMAKE_INSTALL_PREFIX STREQUAL "/usr")
  message(FATAL_ERROR
    "The secure plugin runtime must be built for the canonical /usr prefix; use DESTDIR to stage it")
endif()
if(NOT CMAKE_INSTALL_LIBDIR STREQUAL "lib")
  message(FATAL_ERROR
    "The secure plugin runtime must use the canonical /usr/lib package root")
endif()

set(OMARCHY_PLUGIN_INSTALL_ROOT
  "lib/omarchy/plugin-security/${PROJECT_VERSION}")

set(OMARCHY_PLUGIN_PACKAGED_WORKER
  "/usr/${OMARCHY_PLUGIN_INSTALL_ROOT}/bin/omarchy-plugin-qml-worker")
install(CODE [[
  if(NOT CMAKE_INSTALL_PREFIX STREQUAL "/usr")
    message(FATAL_ERROR
      "The secure plugin runtime must be installed with its canonical /usr prefix; use DESTDIR to stage it")
  endif()
]])
configure_file(cmake/runtime_paths.hpp.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/omarchy/plugin_runtime/runtime_paths.hpp"
  @ONLY)
configure_file(packaging/runtime-paths-v1.txt.in
  "${CMAKE_CURRENT_BINARY_DIR}/generated/runtime-paths-v1.txt"
  @ONLY)
add_library(omarchy-plugin-runtime-paths INTERFACE)
add_library(Omarchy::PluginRuntimePaths ALIAS omarchy-plugin-runtime-paths)
target_include_directories(omarchy-plugin-runtime-paths INTERFACE
  "${CMAKE_CURRENT_BINARY_DIR}/generated")

if(OMARCHY_PLUGIN_QT_MIN_VERSION)
  find_package(Qt6 ${OMARCHY_PLUGIN_QT_MIN_VERSION} REQUIRED COMPONENTS Core DBus Gui Qml Quick)
  qt_standard_project_setup(REQUIRES ${OMARCHY_PLUGIN_QT_MIN_VERSION})
else()
  find_package(Qt6 REQUIRED COMPONENTS Core DBus Gui Qml Quick)
  qt_standard_project_setup()
endif()

install(FILES
  packaging/runtime-dependencies-v1.txt
  "${CMAKE_CURRENT_BINARY_DIR}/generated/runtime-paths-v1.txt"
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/metadata")

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

add_subdirectory(presentation)

function(omarchy_plugin_target_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

install(FILES
  shell/SecurePluginHost.qml
  shell/SecureSurfacePolicy.js
  shell/SecureBarSurface.qml
  shell/SecurePanelSurface.qml
  shell/SecureOverlaySurface.qml
  shell/TrustedSurfaceInputMask.qml
  DESTINATION "${OMARCHY_PLUGIN_INSTALL_ROOT}/shell")

# Contract owners add their directory without changing this shared root. A missing
# directory means that security subsystem has not landed yet, not that it is optional
# at runtime.
foreach(contract IN ITEMS manifest wire surface permissions sandbox)
  string(TOUPPER "${contract}" contract_upper)
  option("OMARCHY_BUILD_${contract_upper}_CONTRACT" "Build the ${contract} contract when present" ON)
  if(OMARCHY_BUILD_${contract_upper}_CONTRACT AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/contracts/${contract}/CMakeLists.txt")
    add_subdirectory("contracts/${contract}")
  endif()
endforeach()

add_subdirectory(policy)

if(TARGET omarchy-plugin-permission-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/contracts/capability-definitions/CMakeLists.txt")
  add_subdirectory(contracts/capability-definitions)
endif()

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-permission-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/broker/CMakeLists.txt")
  add_subdirectory(broker)
endif()

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-surface-contract
    AND TARGET omarchy-plugin-sandbox-policy)
  add_subdirectory(worker)
endif()

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-surface-contract)
  add_subdirectory(trusted-bridge)
  add_subdirectory(surface-host)
endif()

if(TARGET omarchy-plugin-sandbox-policy
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/launcher/CMakeLists.txt")
  add_subdirectory(launcher)
endif()

if(TARGET omarchy-plugin-capability-definitions
    AND TARGET omarchy-plugin-launcher
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/provider-host/CMakeLists.txt")
  add_subdirectory(provider-host)
endif()

if(TARGET omarchy-plugin-broker-core
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/providers/CMakeLists.txt")
  add_subdirectory(providers)
endif()

add_subdirectory(discovery)

if(TARGET omarchy-plugin-broker-core
    AND TARGET omarchy-plugin-providers
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/broker-runtime/CMakeLists.txt")
  add_subdirectory(broker-runtime)
endif()

if(TARGET omarchy-plugin-broker-runtime
    AND TARGET omarchy-plugin-surface-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/host-session/CMakeLists.txt")
  add_subdirectory(host-session)
endif()

if(TARGET omarchy-plugin-launcher
    AND TARGET omarchy-plugin-broker-core
    AND TARGET omarchy-plugin-surface-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/channel-integration/CMakeLists.txt")
  add_subdirectory(channel-integration)
endif()

if(TARGET omarchy-plugin-host-session
    AND TARGET omarchy-plugin-trusted-bridge
    AND TARGET omarchy-plugin-authenticated-session
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/bridge/CMakeLists.txt")
  add_subdirectory(bridge)
endif()

# The Quickshell host is a shared QML module which embeds the native runtime.
# Keep that linkage requirement owned here, where the complete runtime
# target graph is visible, instead of relying on a global compiler setting.
set(plugin_host_embedded_targets
  omarchy-plugin-manifest-contract
  omarchy-plugin-wire
  omarchy-plugin-surface-contract
  omarchy-plugin-permission-contract
  omarchy-plugin-sandbox-policy
  omarchy-plugin-capability-definitions
  omarchy-plugin-provider-host
  omarchy-plugin-broker-core
  omarchy-plugin-trusted-bridge
  omarchy-plugin-surface-host
  omarchy-plugin-launcher
  omarchy-plugin-providers
  omarchy-plugin-discovery
  omarchy-plugin-broker-runtime
  omarchy-plugin-activation-snapshot
  omarchy-plugin-host-session
  omarchy-plugin-channel-integration
  omarchy-plugin-authenticated-session
)
foreach(target IN LISTS plugin_host_embedded_targets)
  if(TARGET "${target}")
    set_target_properties("${target}" PROPERTIES POSITION_INDEPENDENT_CODE ON)
  endif()
endforeach()

if(BUILD_TESTING)
  add_subdirectory(tests/adversarial)
  add_subdirectory(tests)
endif()
