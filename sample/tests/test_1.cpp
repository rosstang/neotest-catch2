#include "catch2test.hpp"
#include <iostream>

using namespace std;

namespace test {

TEST_CASE(
    "Testing_a_really_long_test_name_that_may_causes_liine_wrap_in_catch2_and_console_width_need_to_set_to_a_large_value_like_3000_to_work_around_the_line_wrap_issue_as_there_maybe_hyphen_added_which_is_difficult_to_remove") {
    int a = 0;
    cout << "writing to stdout" << endl;
    cout << "writing to stderr" << endl;
    REQUIRE(a == 0);
}

}  // namespace test
