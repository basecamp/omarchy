cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_product_fixtures LANGUAGES CXX)

include(CTest)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick)

option(PLUGIN_SECURITY_ENABLE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(NOT TARGET omarchy-plugin-manifest-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../contracts/manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest")
endif()

set(CMAKE_AUTOMOC ON)

add_executable(omarchy-plugin-product-fixtures-test
  tests/product_fixtures_test.cpp
)
target_compile_features(omarchy-plugin-product-fixtures-test PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-product-fixtures-test PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
if(PLUGIN_SECURITY_ENABLE_SANITIZERS)
  target_compile_options(omarchy-plugin-product-fixtures-test PRIVATE
    -fsanitize=address,undefined
    -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-product-fixtures-test PRIVATE
    -fsanitize=address,undefined
  )
endif()
target_compile_definitions(omarchy-plugin-product-fixtures-test PRIVATE
  OMARCHY_PRODUCT_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(omarchy-plugin-product-fixtures-test PRIVATE
  Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick
  omarchy-plugin-manifest-contract
)

add_test(NAME plugin-product-fixtures
  COMMAND omarchy-plugin-product-fixtures-test
)
set_tests_properties(plugin-product-fixtures PROPERTIES
  ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_QPA_PLATFORMTHEME=none;QSG_RHI_BACKEND=software;QSG_SOFTWARE_RENDERER_FORCE_PARTIAL_UPDATES=0"
  LABELS "unit;qml;fixtures;security"
)
