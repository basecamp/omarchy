#pragma once

#include <cstddef>
#include <cstdint>
#include <limits>
#include <optional>
#include <type_traits>
#include <utility>

namespace omarchy::plugin_runtime::surface {

template <typename T>
  requires std::is_unsigned_v<T>
constexpr std::optional<T> checked_add(T left, T right) {
  if (right > std::numeric_limits<T>::max() - left) {
    return std::nullopt;
  }
  return left + right;
}

template <typename T>
  requires std::is_unsigned_v<T>
constexpr std::optional<T> checked_multiply(T left, T right) {
  if (left != 0 && right > std::numeric_limits<T>::max() / left) {
    return std::nullopt;
  }
  return left * right;
}

template <typename T>
  requires std::is_unsigned_v<T>
constexpr std::optional<T> checked_align_up(T value, T alignment) {
  if (alignment == 0 || (alignment & (alignment - 1)) != 0) {
    return std::nullopt;
  }
  const auto adjusted = checked_add(value, alignment - 1);
  if (!adjusted) {
    return std::nullopt;
  }
  return *adjusted & ~(alignment - 1);
}

template <typename Target, typename Source>
constexpr std::optional<Target> checked_cast(Source value) {
  static_assert(std::is_integral_v<Target> && std::is_integral_v<Source>);
  if (!std::in_range<Target>(value)) {
    return std::nullopt;
  }
  return static_cast<Target>(value);
}

} // namespace omarchy::plugin_runtime::surface
