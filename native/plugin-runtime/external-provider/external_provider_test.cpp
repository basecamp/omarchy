#include "external_provider.hpp"
#include <array>
#include <fstream>
#include <stdexcept>
#include <sys/socket.h>
#include <unistd.h>
using namespace omarchy::plugins;
namespace {
void require(bool v, std::string_view m) {
  if (!v)
    throw std::runtime_error(std::string(m));
}
definitions::Digest digest(char c) {
  return definitions::Digest(std::string(64, c));
}
bool rx(int fd, std::span<std::byte> s, std::span<const std::byte> &f) {
  auto n = recv(fd, s.data(), s.size(), 0);
  if (n <= 0)
    return false;
  f = std::span<const std::byte>(s).first(n);
  return true;
}
bool tx(int fd, std::span<const std::byte> f) {
  return write(fd, f.data(), f.size()) ==
         static_cast<ssize_t>(f.size());
}
} // namespace
int main(int argc, char **) {
  if (argc == 2) {
    std::array<std::byte, external_provider::kMaximumFrameBytes> b{};
    std::span<const std::byte> f;
    if (!rx(3, b, f) || !tx(3, f)) {
      return 70;
    }
    if (!rx(3, b, f)) {
      return 71;
    }
    external_provider::RequestFrame q{};
    if (!external_provider::decode_request(f, q) ||
        q.service_id.view() != "local.fake-provider" ||
        q.operation.view() != "status") {
      return 72;
    }
    std::array<std::byte, definitions::kMaximumDynamicPayloadBytes>
        payload_copy{};
    std::ranges::copy(q.payload, payload_copy.begin());
    external_provider::ReplyFrame p{
        q.correlation, q.host_nonce,
        std::span(payload_copy).first(q.payload.size())};
    size_t n = 0;
    if (!external_provider::encode_reply(p, b, n) ||
        !tx(3, std::span(b).first(n))) {
      return 73;
    }
    return 0;
  }
  const auto self = std::filesystem::canonical("/proc/self/exe");
  std::ifstream stream(self, std::ios::binary);
  const std::string bytes((std::istreambuf_iterator<char>(stream)), {});
  external_provider::Registration r{
      .service_id = definitions::Name("local.fake-provider"),
      .adapter = {.adapter_class = definitions::Name("fake-bounded-harness"),
                  .implementation_digest = digest('d'),
                  .abi_version = 1},
      .executable = self,
      .executable_digest = definitions::Digest(manifest::sha256_hex(bytes)),
      .expected_uid = static_cast<std::uint32_t>(getuid()),
      .protocol_version = 2};
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId("org.example.plugin"),
      .revision = digest('b'),
      .policy_fingerprint = digest('c'),
      .generation = 2};
  const std::array payload{std::byte{0x2a}, std::byte{0x2b}};
  definitions::AuthorizedDynamicRequest q{
      .authorization = {.binding = binding,
                        .definition = {.canonical_name = definitions::Name(
                                           "local.my-harness"),
                                       .definition_generation = 1,
                                       .definition_digest = digest('e')},
                        .grant_epoch = 4},
      .operation = "status",
      .demand_scope = "profile=my-harness-v1",
      .payload = payload};
  std::array<std::byte, 16> out{};
  size_t n = 0;
  std::array<std::byte, external_provider::kMaximumFrameBytes> preflight{};
  std::array<std::byte, external_provider::kNonceBytes> preflight_nonce{};
  external_provider::RequestFrame preflight_request{
      r.service_id,
      r.adapter,
      q.authorization,
      definitions::Name(q.operation),
      definitions::CanonicalScope(q.demand_scope),
      q.payload,
      1,
      preflight_nonce};
  require(external_provider::encode_request(preflight_request, preflight, n),
          "preflight encode failed");
  const auto result =
      external_provider::invoke(r, q, out, n, std::chrono::seconds(1), 4);
  require(result == external_provider::Result::completed && n == 2 &&
              out[0] == payload[0],
          "authenticated provider E2E failed: " +
              std::to_string(static_cast<int>(result)));
  require(external_provider::invoke(r, q, out, n, std::chrono::seconds(1), 5) ==
              external_provider::Result::revoked,
          "stale epoch reached provider");
  std::array<std::byte, external_provider::kMaximumFrameBytes> b{};
  std::array<std::byte, external_provider::kNonceBytes> nonce{};
  nonce[0] = std::byte{1};
  external_provider::RequestFrame canonical{
      r.service_id,
      r.adapter,
      q.authorization,
      definitions::Name(q.operation),
      definitions::CanonicalScope(q.demand_scope),
      payload,
      9,
      nonce};
  require(external_provider::encode_request(canonical, b, n),
          "request encode failed");
  external_provider::RequestFrame decoded{};
  require(external_provider::decode_request(std::span(b).first(n), decoded) &&
              decoded.correlation == 9 &&
              decoded.authorization.binding == binding,
          "request round trip failed");
  require(
      !external_provider::decode_request(std::span(b).first(n - 1), decoded),
      "truncation decoded");
  b[n] = std::byte{};
  require(
      !external_provider::decode_request(std::span(b).first(n + 1), decoded),
      "trailing byte decoded");
  require(external_provider::encode_handshake(r, nonce, b, n) &&
              external_provider::verify_handshake_echo(r, nonce,
                                                       std::span(b).first(n)),
          "handshake failed");
  auto wrong = nonce;
  wrong[1] = std::byte{1};
  require(!external_provider::verify_handshake_echo(r, wrong,
                                                    std::span(b).first(n)),
          "wrong nonce verified");
  r.executable = "/bin/sh";
  require(!external_provider::valid_registration(r), "shell registered");
  return 0;
}
