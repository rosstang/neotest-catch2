#if CATCH2_VERSION_MAJOR == 3
  #include <catch2/catch_test_macros.hpp>
  #include <catch2/catch_template_test_macros.hpp>
#elif CATCH2_VERSION_MAJOR == 2
  #include <catch2/catch.hpp>
#else
  #error Unsupported version of Catch2
#endif

