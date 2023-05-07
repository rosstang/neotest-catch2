#include <catch2/catch_test_macros.hpp>
#include <iostream>

using namespace std;

namespace test {

TEST_CASE(
    "Testing a really long test name that may causes line wrap in catch2 "
    "listing when executing the executable with --list-tests") {
    int a = 0;
    cout << "writing to stdout" << endl;
    cout << "writing to stderr" << endl;
    REQUIRE(a == 0);
}

}  // namespace test
