cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_grant_store LANGUAGES CXX)
  include(CTest)
  include(GNUInstallDirs)
endif()

if(NOT TARGET omarchy-plugin-permission-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../contracts/permissions"
                   "${CMAKE_CURRENT_BINARY_DIR}/permission-contract")
endif()

option(PLUGIN_SECURITY_GRANT_STORE_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-grant-store STATIC grant_store.cpp)
target_include_directories(omarchy-plugin-grant-store PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-grant-store PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-grant-store PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-grant-store PUBLIC
  omarchy-plugin-permission-contract
)

add_executable(omarchy-plugin-permission-store grant_store_cli.cpp)
target_compile_features(omarchy-plugin-permission-store PRIVATE cxx_std_20)
target_compile_options(omarchy-plugin-permission-store PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-permission-store PRIVATE
  omarchy-plugin-grant-store
)

if(PLUGIN_SECURITY_GRANT_STORE_SANITIZERS)
  foreach(target IN ITEMS omarchy-plugin-grant-store omarchy-plugin-permission-store)
    target_compile_options(${target} PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(${target} PRIVATE -fsanitize=address,undefined)
  endforeach()
endif()

install(TARGETS omarchy-plugin-permission-store
        RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}")

if(BUILD_TESTING)
  add_executable(omarchy-plugin-grant-store-test grant_store_test.cpp)
  target_compile_features(omarchy-plugin-grant-store-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-grant-store-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-grant-store-test PRIVATE
    omarchy-plugin-grant-store
  )
  if(PLUGIN_SECURITY_GRANT_STORE_SANITIZERS)
    target_compile_options(omarchy-plugin-grant-store-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-grant-store-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-grant-store COMMAND omarchy-plugin-grant-store-test)
  set_tests_properties(plugin-grant-store PROPERTIES
    TIMEOUT 20
    LABELS "unit;integration;adversarial"
  )
  add_test(NAME plugin-grant-store-cli
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/grant_store_cli_test.sh"
            "$<TARGET_FILE:omarchy-plugin-permission-store>"
  )
  set_tests_properties(plugin-grant-store-cli PROPERTIES
    TIMEOUT 20
    LABELS "integration;adversarial;cli"
  )
endif()
