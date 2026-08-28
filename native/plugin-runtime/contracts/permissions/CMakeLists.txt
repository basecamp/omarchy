cmake_minimum_required(VERSION 3.20)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  project(omarchy_plugin_permission_contract LANGUAGES CXX)
endif()

include(CTest)

if(NOT TARGET omarchy-plugin-manifest-contract)
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../manifest"
                   "${CMAKE_CURRENT_BINARY_DIR}/manifest")
endif()

option(PLUGIN_SECURITY_PERMISSION_SANITIZERS
       "Enable AddressSanitizer and UndefinedBehaviorSanitizer" OFF)

add_library(omarchy-plugin-permission-contract STATIC permission_contract.cpp)
target_include_directories(omarchy-plugin-permission-contract PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
target_compile_features(omarchy-plugin-permission-contract PUBLIC cxx_std_20)
target_compile_options(omarchy-plugin-permission-contract PRIVATE
  -Wall -Wextra -Wpedantic -Werror
)
target_link_libraries(omarchy-plugin-permission-contract PUBLIC
  omarchy-plugin-manifest-contract
)

if(PLUGIN_SECURITY_PERMISSION_SANITIZERS)
  target_compile_options(omarchy-plugin-permission-contract PRIVATE
    -fsanitize=address,undefined -fno-omit-frame-pointer
  )
  target_link_options(omarchy-plugin-permission-contract PRIVATE
    -fsanitize=address,undefined
  )
endif()

if(BUILD_TESTING)
  add_executable(omarchy-plugin-permission-contract-test permission_contract_test.cpp)
  target_compile_features(omarchy-plugin-permission-contract-test PRIVATE cxx_std_20)
  target_compile_options(omarchy-plugin-permission-contract-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror
  )
  target_link_libraries(omarchy-plugin-permission-contract-test PRIVATE
    omarchy-plugin-permission-contract
  )
  target_compile_definitions(omarchy-plugin-permission-contract-test PRIVATE
    POLICY_FINGERPRINT_GOLDEN="878c1ce13a505e4084ed8f5babb0afca1a4850227a5ba17d1c391490f935b286"
    GRANT_FINGERPRINT_GOLDEN="b5e153eed88c957910b10a5c6efb1773210417591c8bd26e321e4aa7abd7e4bf"
    AUDIT_FINGERPRINT_GOLDEN="ae35a454833ed2ff344fa510a931237b3b977d6213058f90ce6af4984a2a4161"
  )
  if(PLUGIN_SECURITY_PERMISSION_SANITIZERS)
    target_compile_options(omarchy-plugin-permission-contract-test PRIVATE
      -fsanitize=address,undefined -fno-omit-frame-pointer
    )
    target_link_options(omarchy-plugin-permission-contract-test PRIVATE
      -fsanitize=address,undefined
    )
  endif()
  add_test(NAME plugin-permission-contract
           COMMAND omarchy-plugin-permission-contract-test)
  set_tests_properties(plugin-permission-contract PROPERTIES
    TIMEOUT 15
    LABELS "unit;protocol;adversarial"
  )
endif()
