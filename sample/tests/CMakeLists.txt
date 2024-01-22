add_executable(testing
    test_1.cpp
    test_2.cpp
    )
target_link_libraries(testing PRIVATE
    Catch2::Catch2WithMain
    )

set_property(GLOBAL PROPERTY CTEST_TARGETS_ADDED 1)
include(CTest)
catch_discover_tests(testing)

target_compile_definitions(testing PRIVATE CATCH2_VERSION_MAJOR=${CATCH2_MAJOR_VERSION})
