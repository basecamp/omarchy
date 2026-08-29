#pragma once
#include "dynamic_activation.hpp"
#include <chrono>
#include <filesystem>
#include <span>

namespace omarchy::plugins::external_provider {
using definitions::Digest;
struct Registration {
  definitions::Name service_id;
  definitions::AdapterBinding adapter;
  std::filesystem::path executable;
  Digest executable_digest;
  std::uint32_t expected_uid = 0;
  std::uint32_t protocol_version = 0;
};
enum class Result : std::uint8_t { completed, invalid_registration, identity_mismatch, timeout, crashed, malformed, revoked };
[[nodiscard]] bool valid_registration(const Registration &value);
[[nodiscard]] Result invoke(const Registration &registration,
                            const definitions::AuthorizedDynamicRequest &request,
                            std::span<std::byte> response, std::size_t &written,
                            std::chrono::milliseconds timeout,
                            std::uint64_t current_epoch);
} // namespace omarchy::plugins::external_provider
