cmake_minimum_required(VERSION 3.20)

project(omarchy_plugin_bwrap_identity_spike LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(JSON_C REQUIRED IMPORTED_TARGET json-c)

add_executable(plugin-bwrap-identity-spike bwrap_identity_spike.cpp)
target_compile_features(plugin-bwrap-identity-spike PRIVATE cxx_std_20)
target_link_libraries(plugin-bwrap-identity-spike PRIVATE PkgConfig::JSON_C)
target_compile_options(plugin-bwrap-identity-spike PRIVATE
  -Wall
  -Wextra
  -Wpedantic
  -Werror
)

enable_testing()
add_test(NAME plugin-bwrap-identity-contract COMMAND plugin-bwrap-identity-spike)
add_test(NAME plugin-bwrap-identity-reserved-fd-collision
  COMMAND plugin-bwrap-identity-spike --occupied-reserved)
add_test(NAME plugin-bwrap-identity-closed-stdin
  COMMAND plugin-bwrap-identity-spike --closed-stdin)
add_test(NAME plugin-bwrap-identity-closed-stdout
  COMMAND plugin-bwrap-identity-spike --closed-stdout)
add_test(NAME plugin-bwrap-identity-closed-stderr
  COMMAND plugin-bwrap-identity-spike --closed-stderr)
set_tests_properties(
  plugin-bwrap-identity-contract
  plugin-bwrap-identity-reserved-fd-collision
  plugin-bwrap-identity-closed-stdin
  plugin-bwrap-identity-closed-stdout
  plugin-bwrap-identity-closed-stderr
  PROPERTIES TIMEOUT 15)
