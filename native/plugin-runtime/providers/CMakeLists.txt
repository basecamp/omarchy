cmake_minimum_required(VERSION 3.24)

project(omarchy_plugin_providers LANGUAGES CXX)

include(CTest)

find_package(Qt6 REQUIRED COMPONENTS Core DBus)
find_package(CURL REQUIRED)

if(NOT TARGET omarchy-plugin-broker-core)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../broker"
                   "${CMAKE_CURRENT_BINARY_DIR}/broker")
endif()

if(NOT TARGET omarchy-plugin-capability-definitions)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/capability-definitions"
                   "${CMAKE_CURRENT_BINARY_DIR}/capability-definitions")
endif()

add_library(omarchy-plugin-providers STATIC
  src/audio_device_provider.cpp
  src/bluez_audio_backend.cpp
  src/github_cli_backend.cpp
  src/github_provider.cpp
  src/private_storage_backend.cpp
  src/radio_live_backend.cpp
  src/radio_provider.cpp
  src/provider_set.cpp
  src/provider_schemas.cpp
)
target_compile_features(omarchy-plugin-providers PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-providers PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_include_directories(omarchy-plugin-providers PUBLIC include)
target_link_libraries(omarchy-plugin-providers PUBLIC
  omarchy-plugin-broker-core
  omarchy-plugin-capability-definitions
  CURL::libcurl
  Qt6::Core
  Qt6::DBus
)

if(BUILD_TESTING)
  add_executable(omarchy-plugin-audio-device-provider-test
    tests/audio_device_provider_test.cpp
  )
  target_compile_features(omarchy-plugin-audio-device-provider-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-audio-device-provider-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-audio-device-provider-test PRIVATE omarchy-plugin-providers Qt6::Core)
  add_test(NAME plugin-audio-device-provider COMMAND omarchy-plugin-audio-device-provider-test)

  add_executable(omarchy-plugin-bluez-audio-backend-test
    tests/bluez_audio_backend_test.cpp
  )
  target_compile_features(omarchy-plugin-bluez-audio-backend-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-bluez-audio-backend-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-bluez-audio-backend-test PRIVATE omarchy-plugin-providers Qt6::Core)
  add_test(NAME plugin-bluez-audio-backend COMMAND omarchy-plugin-bluez-audio-backend-test)

  add_executable(omarchy-plugin-bluez-audio-live-compat
    tests/bluez_audio_live_compat.cpp
  )
  target_compile_features(omarchy-plugin-bluez-audio-live-compat PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-bluez-audio-live-compat PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-bluez-audio-live-compat PRIVATE omarchy-plugin-providers Qt6::Core)

  add_executable(omarchy-plugin-github-provider-test
    tests/github_provider_test.cpp
  )
  target_compile_features(omarchy-plugin-github-provider-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-github-provider-test PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(omarchy-plugin-github-provider-test PRIVATE omarchy-plugin-providers Qt6::Core)
  add_test(NAME plugin-github-provider COMMAND omarchy-plugin-github-provider-test)

  add_executable(omarchy-plugin-providers-test tests/provider_set_test.cpp)
  target_compile_features(omarchy-plugin-providers-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-providers-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-providers-test PRIVATE
    omarchy-plugin-providers
  )
  add_test(NAME plugin-providers COMMAND omarchy-plugin-providers-test)
  set_tests_properties(plugin-providers PROPERTIES
    LABELS "unit;protocol;adversarial;providers"
  )

  add_executable(omarchy-plugin-provider-schema-test
    tests/provider_schema_test.cpp
  )
  target_compile_features(omarchy-plugin-provider-schema-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-provider-schema-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-provider-schema-test PRIVATE
    omarchy-plugin-providers
  )
  add_test(NAME plugin-provider-schemas
    COMMAND omarchy-plugin-provider-schema-test
  )
  set_tests_properties(plugin-provider-schemas PROPERTIES
    LABELS "unit;protocol;adversarial;providers;golden"
  )

  add_executable(omarchy-plugin-radio-provider-test
    tests/radio_provider_test.cpp
  )
  target_compile_features(omarchy-plugin-radio-provider-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-radio-provider-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-radio-provider-test PRIVATE
    omarchy-plugin-providers Qt6::Core
  )
  add_test(NAME plugin-radio-provider COMMAND omarchy-plugin-radio-provider-test)
  set_tests_properties(plugin-radio-provider PROPERTIES
    LABELS "unit;protocol;adversarial;providers;network;media"
  )

  add_executable(omarchy-plugin-radio-live-compat
    tests/radio_live_compat.cpp
  )
  target_compile_features(omarchy-plugin-radio-live-compat PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-radio-live-compat PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-radio-live-compat PRIVATE
    omarchy-plugin-providers Qt6::Core
  )

  add_executable(omarchy-plugin-private-storage-test
    tests/private_storage_backend_test.cpp
  )
  target_compile_features(omarchy-plugin-private-storage-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-private-storage-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-private-storage-test PRIVATE
    omarchy-plugin-providers
  )
  add_test(NAME plugin-private-storage
    COMMAND omarchy-plugin-private-storage-test
  )
  set_tests_properties(plugin-private-storage PROPERTIES
    LABELS "unit;adversarial;providers;filesystem"
  )
endif()
