#include <catch2/catch_template_test_macros.hpp>
#include <iostream>

using namespace std;

TEMPLATE_TEST_CASE("Testing template tests", "", int, bool, char) {
    cout << "hello" << endl;
    cerr << " world" << endl;
    int a = 10;
    SECTION("S1") {
        REQUIRE(a == 10);
        SECTION("S2") { REQUIRE(a == 0); }
    }

    SECTION("S2") {
        REQUIRE(a == 10);
        REQUIRE(a == 0);
    }
}
