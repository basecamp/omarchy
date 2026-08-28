cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_update_hardening LANGUAGES CXX)

include(CTest)

if(NOT TARGET omarchy-plugin-lifecycle)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../lifecycle"
                   "${CMAKE_CURRENT_BINARY_DIR}/lifecycle")
endif()

option(PLUGIN_SECURITY_UPDATE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-update-hardening STATIC update_hardening.cpp)
target_include_directories(omarchy-plugin-update-hardening PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-update-hardening PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-update-hardening PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-update-hardening PUBLIC
  omarchy-plugin-lifecycle
)

if(PLUGIN_SECURITY_UPDATE_SANITIZERS)
  target_compile_options(omarchy-plugin-update-hardening PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-update-hardening PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-update-hardening-test update_hardening_test.cpp)
  target_compile_features(omarchy-plugin-update-hardening-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-update-hardening-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_compile_definitions(omarchy-plugin-update-hardening-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal"
  )
  target_link_libraries(omarchy-plugin-update-hardening-test PRIVATE
    omarchy-plugin-update-hardening
  )
  if(PLUGIN_SECURITY_UPDATE_SANITIZERS)
    target_compile_options(omarchy-plugin-update-hardening-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-update-hardening-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-update-hardening COMMAND omarchy-plugin-update-hardening-test)
  set_tests_properties(plugin-update-hardening PROPERTIES
    TIMEOUT 30
    LABELS "unit;integration;adversarial;lifecycle;update"
  )
endif()
