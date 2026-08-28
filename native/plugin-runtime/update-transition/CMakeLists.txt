cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_update_transition LANGUAGES CXX)
include(CTest)

option(PLUGIN_SECURITY_TRANSITION_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

if(NOT TARGET omarchy-plugin-channel-integration)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../channel-integration"
                   "${CMAKE_CURRENT_BINARY_DIR}/channel-integration")
endif()
if(NOT TARGET omarchy-plugin-lifecycle)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../lifecycle"
                   "${CMAKE_CURRENT_BINARY_DIR}/lifecycle")
endif()
if(NOT TARGET omarchy-plugin-broker-runtime)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker-runtime"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker-runtime")
endif()
if(NOT TARGET omarchy-plugin-supervisor-health)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../supervisor-health"
                   "${CMAKE_CURRENT_BINARY_DIR}/supervisor-health")
endif()

add_library(omarchy-plugin-update-transition STATIC update_transition.cpp)
target_include_directories(omarchy-plugin-update-transition PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-update-transition PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-update-transition PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-update-transition PUBLIC
  omarchy-plugin-channel-integration
  omarchy-plugin-lifecycle
  omarchy-plugin-broker-runtime
  omarchy-plugin-supervisor-health
)

if(PLUGIN_SECURITY_TRANSITION_SANITIZERS)
  target_compile_options(omarchy-plugin-update-transition PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-update-transition PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-update-transition-test update_transition_test.cpp)
  target_compile_features(omarchy-plugin-update-transition-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-update-transition-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_compile_definitions(omarchy-plugin-update-transition-test PRIVATE
    MANIFEST_V2_FIXTURE_ROOT="${CMAKE_CURRENT_SOURCE_DIR}/../contracts/manifest/fixtures/valid-minimal"
  )
  target_link_libraries(omarchy-plugin-update-transition-test PRIVATE
    omarchy-plugin-update-transition
  )
  if(PLUGIN_SECURITY_TRANSITION_SANITIZERS)
    target_compile_options(omarchy-plugin-update-transition-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-update-transition-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-update-transition COMMAND omarchy-plugin-update-transition-test)
  set_tests_properties(plugin-update-transition PROPERTIES
    TIMEOUT 30
    LABELS "integration;adversarial;lifecycle;update;broker;audit;health"
  )
endif()
