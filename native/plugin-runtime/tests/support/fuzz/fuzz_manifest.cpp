#include "manifest_contract.hpp"

#include <cstddef>
#include <cstdint>
#include <exception>
#include <string_view>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data,
                                      std::size_t size) {
  const auto *characters = reinterpret_cast<const char *>(data);
  try {
    static_cast<void>(omarchy::plugins::manifest::parse_manifest_v2(
        std::string_view(characters, size)));
  } catch (const std::exception &) {
  }
  return 0;
}
