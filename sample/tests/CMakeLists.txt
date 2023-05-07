add_executable(testing
    test_a_really_long_filename_tests_that_may_causes_line_wrap_in_catch2_listing.cpp
    test_2.cpp
    )
target_link_libraries(testing PRIVATE
    Catch2::Catch2WithMain
    )

set_property(GLOBAL PROPERTY CTEST_TARGETS_ADDED 1)
include(CTest)
catch_discover_tests(testing)
