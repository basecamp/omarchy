#pragma once
#include "audit_store.hpp"
#include "dynamic_activation.hpp"
#include <array>
#include <chrono>
#include <filesystem>
#include <span>

namespace omarchy::plugins::external_provider {
using definitions::Digest;
inline constexpr std::size_t kNonceBytes = 32;
inline constexpr std::size_t kMaximumFrameBytes = 49152;
struct Registration {
  definitions::Name service_id;
  definitions::AdapterBinding adapter;
  std::filesystem::path executable;
  Digest executable_digest;
  std::uint32_t expected_uid = 0;
  std::uint32_t protocol_version = 0;
};
struct RequestFrame {
  definitions::Name service_id;
  definitions::AdapterBinding adapter;
  definitions::DynamicAuthorizationContext authorization;
  definitions::Name operation;
  definitions::CanonicalScope demand_scope;
  std::span<const std::byte> payload;
  std::uint64_t correlation = 0;
  std::array<std::byte, kNonceBytes> host_nonce{};
};
struct ReplyFrame {
  std::uint64_t correlation = 0;
  std::array<std::byte, kNonceBytes> host_nonce{};
  std::span<const std::byte> payload;
};
enum class Result : std::uint8_t {
  completed,
  invalid_registration,
  identity_mismatch,
  timeout,
  crashed,
  malformed,
  revoked,
  audit_failed
};
struct InvocationGuard {
  audit::AuditStore *audit = nullptr;
  std::uint64_t correlation = 0;
  bool (*still_authorized)(const definitions::DynamicAuthorizationContext &,
                           void *) noexcept = nullptr;
  void *authorization_context = nullptr;
};
[[nodiscard]] bool valid_registration(const Registration &);
[[nodiscard]] bool encode_handshake(const Registration &,
                                    std::span<const std::byte, kNonceBytes>,
                                    std::span<std::byte>, std::size_t &);
[[nodiscard]] bool
verify_handshake_echo(const Registration &,
                      std::span<const std::byte, kNonceBytes>,
                      std::span<const std::byte>);
[[nodiscard]] bool encode_request(const RequestFrame &, std::span<std::byte>,
                                  std::size_t &);
[[nodiscard]] bool decode_request(std::span<const std::byte>, RequestFrame &);
[[nodiscard]] bool encode_reply(const ReplyFrame &, std::span<std::byte>,
                                std::size_t &);
[[nodiscard]] bool decode_reply(std::span<const std::byte>, ReplyFrame &);
[[nodiscard]] Result invoke(const Registration &,
                            const definitions::AuthorizedDynamicRequest &,
                            std::span<std::byte>, std::size_t &,
                            std::chrono::milliseconds, std::uint64_t,
                            std::uint64_t correlation = 1);
[[nodiscard]] Result
invoke_audited(const Registration &,
               const definitions::AuthorizedDynamicRequest &,
               std::span<std::byte>, std::size_t &, std::chrono::milliseconds,
               std::uint64_t, const InvocationGuard &);
} // namespace omarchy::plugins::external_provider
