#include <unistd.h>
#include <catch2/catch_template_test_macros.hpp>
#include <iostream>
#include <type_traits>

using namespace std;

TEMPLATE_TEST_CASE("Testing template tests", "", int, bool, char) {
    cout << "hello" << endl;
    cerr << " world" << endl;
    int a = 10;
    SECTION("S1") {
        sleep(1);
        REQUIRE(a == 10);
        SECTION("S2") {
            if constexpr (is_same_v<int, TestType>) {
                REQUIRE(a == 0);
            }
        }
    }

    SECTION("S2") {
        sleep(1);
        REQUIRE(a == 10);
    }
}
