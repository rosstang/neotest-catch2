#include "catch2test.hpp"
#include <unistd.h>
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

TEST_CASE("Test1 3") {
    print_lines(10000);
}

TEST_CASE("Test1 4") {
    print_lines(10000);
}

TEST_CASE("Test1 5") {
    print_lines(10000);
}

TEST_CASE("Test1 6") {
    print_lines(10000);
}

TEST_CASE("Test1 7") {
    print_lines(10000);
}

TEST_CASE("Test1 8") {
    print_lines(10000);
}

TEST_CASE("Test1 9") {
    print_lines(10000);
}

TEST_CASE("Test1 10") {
    print_lines(10000);
}

TEST_CASE("Test1 11") {
    print_lines(10000);
}
