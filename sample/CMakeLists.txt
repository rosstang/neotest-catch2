cmake_minimum_required(VERSION 3.14.0)

project(cpp LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 17)

include(FetchContent)

set(CATCH_BUILD_STATIC_LIBRARY ON CACHE BOOL "build catch static lib")
FetchContent_Declare(Catch2 URL https://github.com/catchorg/Catch2/archive/refs/tags/v3.3.2.zip)
FetchContent_MakeAvailable(Catch2)
list(APPEND CMAKE_MODULE_PATH ${catch2_SOURCE_DIR}/extras)
include(CTest)
include(Catch)

add_subdirectory(tests)

