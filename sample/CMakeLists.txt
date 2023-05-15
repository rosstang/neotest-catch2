cmake_minimum_required(VERSION 3.14.0)

project(cpp LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 17)

include(FetchContent)

set(CATCH_BUILD_STATIC_LIBRARY ON CACHE BOOL "build catch static lib")

#set(CATCH_CONFIG_CONSOLE_WIDTH 30000)

set(CATCH2_VERSION "2.13.10")
FetchContent_Declare(Catch2 URL https://github.com/catchorg/Catch2/archive/refs/tags/v${CATCH2_VERSION}.zip)
FetchContent_GetProperties(Catch2)
if(NOT Catch2_POPULATED)
  FetchContent_Populate(Catch2)
  add_subdirectory(${catch2_SOURCE_DIR} ${catch2_BINARY_DIR})
endif()

# Set the path to the Catch2 CMake modules based on the version
if(CATCH2_VERSION STREQUAL "3.3.2")
    set(CATCH2_CMAKE_MODULE_PATH "${catch2_SOURCE_DIR}/extras")
    set(CATCH2_MAJOR_VERSION 3)
elseif(CATCH2_VERSION STREQUAL "2.13.10")
    set(CATCH2_CMAKE_MODULE_PATH "${catch2_SOURCE_DIR}/contrib")
    set(CATCH2_MAJOR_VERSION 2)
else()
    message(FATAL_ERROR "Invalid Catch2 version: ${CATCH2_VERSION}")
endif()

list(APPEND CMAKE_MODULE_PATH ${CATCH2_CMAKE_MODULE_PATH})

target_compile_definitions(Catch2 INTERFACE CATCH_CONFIG_CONSOLE_WIDTH=3000)

include(CTest)
include(Catch)

add_subdirectory(tests)

