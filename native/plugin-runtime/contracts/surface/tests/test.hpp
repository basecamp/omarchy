#pragma once

#include <cstdlib>
#include <iostream>
#include <string_view>

inline void require(bool condition, std::string_view message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}
