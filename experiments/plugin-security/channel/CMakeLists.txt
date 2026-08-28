cmake_minimum_required(VERSION 3.20)

project(omarchy_plugin_channel_spike LANGUAGES CXX)

add_executable(plugin-channel-spike plugin_channel_spike.cpp)
target_compile_features(plugin-channel-spike PRIVATE cxx_std_20)
target_compile_options(plugin-channel-spike PRIVATE -Wall -Wextra -Wpedantic -Werror)

enable_testing()
add_test(NAME plugin-channel-contract COMMAND plugin-channel-spike --self-test)
