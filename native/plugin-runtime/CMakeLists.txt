cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_runtime VERSION 0.1.0 LANGUAGES CXX)

include(CTest)
include(GNUInstallDirs)

set(OMARCHY_PLUGIN_QT_MIN_VERSION "" CACHE STRING "Optional minimum Qt 6 version required by the package build")

if(OMARCHY_PLUGIN_QT_MIN_VERSION)
  find_package(Qt6 ${OMARCHY_PLUGIN_QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick)
  qt_standard_project_setup(REQUIRES ${OMARCHY_PLUGIN_QT_MIN_VERSION})
else()
  find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)
  qt_standard_project_setup()
endif()

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

set(QT_QML_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml")

function(omarchy_plugin_target_defaults target)
  target_compile_features(${target} PUBLIC cxx_std_20)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror)
endfunction()

configure_file(cmake/PluginRuntimeVersion.h.in generated/omarchy/plugin_runtime/PluginRuntimeVersion.h @ONLY)

add_subdirectory(protocol-version)
add_subdirectory(host)

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

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-surface-contract
    AND TARGET omarchy-plugin-sandbox-policy)
  add_subdirectory(worker)
endif()

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-surface-contract)
  add_subdirectory(trusted-bridge)
  add_subdirectory(render-session)
  add_subdirectory(bridge)
endif()

if(TARGET omarchy-plugin-manifest-contract
    AND TARGET omarchy-plugin-permission-contract
    AND TARGET omarchy-plugin-render-session
    AND TARGET omarchy-plugin-trusted-bridge)
  add_subdirectory(surface-host)
endif()

if(TARGET omarchy-plugin-sandbox-policy
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/launcher/CMakeLists.txt")
  add_subdirectory(launcher)
endif()

if(TARGET omarchy-plugin-wire
    AND TARGET omarchy-plugin-permission-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/broker/CMakeLists.txt")
  add_subdirectory(broker)
endif()
if(TARGET omarchy-plugin-broker-core
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/providers/CMakeLists.txt")
  add_subdirectory(providers)
endif()

add_subdirectory(discovery)
add_subdirectory(revision-store)
add_subdirectory(grants)
add_subdirectory(audit)
add_subdirectory(lifecycle)
add_subdirectory(update-hardening)
add_subdirectory(migration-report)

if(TARGET omarchy-plugin-launcher
    AND TARGET omarchy-plugin-audit-store
    AND TARGET omarchy-plugin-surface-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/supervisor-health/CMakeLists.txt")
  add_subdirectory(supervisor-health)
endif()

if(TARGET omarchy-plugin-broker-core
    AND TARGET omarchy-plugin-providers
    AND TARGET omarchy-plugin-grant-store
    AND TARGET omarchy-plugin-audit-store
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/broker-runtime/CMakeLists.txt")
  add_subdirectory(broker-runtime)
endif()

if(TARGET omarchy-plugin-launcher
    AND TARGET omarchy-plugin-broker-core
    AND TARGET omarchy-plugin-surface-contract
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/channel-integration/CMakeLists.txt")
  add_subdirectory(channel-integration)
endif()

if(TARGET omarchy-plugin-channel-integration
    AND TARGET omarchy-plugin-lifecycle
    AND TARGET omarchy-plugin-broker-runtime
    AND TARGET omarchy-plugin-supervisor-health
    AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/update-transition/CMakeLists.txt")
  add_subdirectory(update-transition)
endif()

if(TARGET omarchy-plugin-channel-integration
    AND TARGET omarchy-plugin-supervisor-health)
  add_subdirectory(headless-slice)
endif()

if(TARGET omarchy-plugin-surface-host)
  add_subdirectory(expressive-surface)
endif()

if(BUILD_TESTING)
  add_subdirectory(fixtures/product)
  add_subdirectory(tests/adversarial)
  add_subdirectory(brokered-action)
  add_subdirectory(vertical-slices/embedded-bar)
  add_subdirectory(render-proof)
  add_subdirectory(tests)
endif()
