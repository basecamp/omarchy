#pragma once

// Private canonical identity validation and fingerprint byte encoding.

#include "permission_contract.hpp"

#include "manifest_contract.hpp"

#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>

namespace omarchy::plugins::permissions::detail {

static inline void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

static inline bool canonical_id(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  bool separator = true;
  for (const unsigned char item : value) {
    const bool alphanumeric =
        (item >= 'a' && item <= 'z') || (item >= '0' && item <= '9');
    const bool current_separator = item == '.' || item == '-' || item == '_';
    if (!alphanumeric && !current_separator)
      return false;
    if (separator && current_separator)
      return false;
    separator = current_separator;
  }
  return !separator && value.front() >= 'a' && value.front() <= 'z';
}

static inline bool canonical_digest(const Digest &digest) {
  return digest.size() == 64 &&
         std::all_of(digest.view().begin(), digest.view().end(),
                     [](const unsigned char item) {
                       return (item >= '0' && item <= '9') ||
                              (item >= 'a' && item <= 'f');
                     });
}

static inline void append_u8(std::string &output, std::uint8_t value) {
  output.push_back(static_cast<char>(value));
}

static inline void append_u16(std::string &output, std::uint16_t value) {
  output.push_back(static_cast<char>(value >> 8));
  output.push_back(static_cast<char>(value & 0xff));
}

static inline void append_u32(std::string &output, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    output.push_back(static_cast<char>((value >> shift) & 0xff));
}

static inline void append_u64(std::string &output, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    output.push_back(static_cast<char>((value >> shift) & 0xff));
}

static inline void append_text(std::string &output, std::string_view value) {
  require(value.size() <= std::numeric_limits<std::uint16_t>::max(),
          "canonical text is too long");
  append_u16(output, static_cast<std::uint16_t>(value.size()));
  output.append(value);
}

static inline std::string fingerprint(std::string bytes) {
  return manifest::sha256_hex(bytes);
}

template <std::size_t Size>
static std::string domain(const char (&value)[Size]) {
  return std::string(value, Size - 1);
}

} // namespace omarchy::plugins::permissions::detail
