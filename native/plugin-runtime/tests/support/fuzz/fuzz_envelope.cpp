#include "omarchy/plugin/wire/envelope.hpp"

#include <cstddef>
#include <cstdint>
#include <span>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data,
                                      std::size_t size) {
  const auto bytes = std::as_bytes(std::span(data, size));
  for (const auto role : {omarchy::plugin::wire::EndpointRole::control,
                          omarchy::plugin::wire::EndpointRole::broker,
                          omarchy::plugin::wire::EndpointRole::render}) {
    static_cast<void>(omarchy::plugin::wire::decode_packet(bytes, role));
  }
  return 0;
}
