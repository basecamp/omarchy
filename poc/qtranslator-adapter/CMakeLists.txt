cmake_minimum_required(VERSION 3.20)

project(omarchy-i18n-poc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.6 REQUIRED COMPONENTS Core Qml)
qt_standard_project_setup(REQUIRES 6.6)

qt_add_qml_module(omarchy-i18n
    URI Omarchy.I18n
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Omarchy/I18n"
    SOURCES
        src/translator.cpp
        src/translator.hpp
)

target_link_libraries(omarchy-i18n PRIVATE Qt6::Core Qt6::Qml)
target_include_directories(omarchy-i18n PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")
