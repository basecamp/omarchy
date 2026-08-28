cmake_minimum_required(VERSION 3.20)

project(omarchy_plugin_envelope_spike LANGUAGES CXX)

add_executable(plugin-envelope-spike envelope_spike.cpp)
target_compile_features(plugin-envelope-spike PRIVATE cxx_std_20)
target_compile_options(plugin-envelope-spike PRIVATE -Wall -Wextra -Wpedantic -Werror)

enable_testing()
add_test(NAME plugin-envelope-contract COMMAND plugin-envelope-spike)
