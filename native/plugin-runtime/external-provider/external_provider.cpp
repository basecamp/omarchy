#include "external_provider.hpp"
#include <algorithm>
#include <array>
#include <cerrno>
#include <fcntl.h>
#include <poll.h>
#include <sys/random.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

namespace omarchy::plugins::external_provider {
namespace {
constexpr std::array<std::byte, 8> hs{
    std::byte{'O'}, std::byte{'M'}, std::byte{'P'}, std::byte{'H'},
    std::byte{'E'}, std::byte{'L'}, std::byte{'O'}, std::byte{2}};
constexpr std::array<std::byte, 8> rq{
    std::byte{'O'}, std::byte{'M'}, std::byte{'P'}, std::byte{'R'},
    std::byte{'E'}, std::byte{'Q'}, std::byte{'S'}, std::byte{2}};
constexpr std::array<std::byte, 8> rp{
    std::byte{'O'}, std::byte{'M'}, std::byte{'P'}, std::byte{'R'},
    std::byte{'E'}, std::byte{'P'}, std::byte{'L'}, std::byte{2}};
struct W {
  std::span<std::byte> b;
  size_t n = 0;
  bool raw(std::span<const std::byte> x) {
    if (n > b.size() || x.size() > b.size() - n)
      return false;
    std::ranges::copy(x, b.begin() + static_cast<std::ptrdiff_t>(n));
    n += x.size();
    return true;
  }
  bool u16(uint16_t x) {
    std::array<std::byte, 2> a{std::byte(x >> 8), std::byte(x)};
    return raw(a);
  }
  bool u32(uint32_t x) {
    std::array<std::byte, 4> a{};
    for (int i = 0; i < 4; i++)
      a[i] = std::byte(x >> ((3 - i) * 8));
    return raw(a);
  }
  bool u64(uint64_t x) {
    std::array<std::byte, 8> a{};
    for (int i = 0; i < 8; i++)
      a[i] = std::byte(x >> ((7 - i) * 8));
    return raw(a);
  }
  bool text(std::string_view x) {
    return !x.empty() && x.size() <= UINT16_MAX && u16(x.size()) &&
           raw(std::as_bytes(std::span(x)));
  }
};
struct R {
  std::span<const std::byte> b;
  size_t n = 0;
  bool raw(size_t z, std::span<const std::byte> &x) {
    if (n > b.size() || z > b.size() - n)
      return false;
    x = b.subspan(n, z);
    n += z;
    return true;
  }
  bool u16(uint16_t &x) {
    std::span<const std::byte> a;
    if (!raw(2, a))
      return false;
    x = (std::to_integer<uint16_t>(a[0]) << 8) |
        std::to_integer<uint16_t>(a[1]);
    return true;
  }
  bool u32(uint32_t &x) {
    std::span<const std::byte> a;
    if (!raw(4, a))
      return false;
    x = 0;
    for (auto q : a)
      x = (x << 8) | std::to_integer<uint32_t>(q);
    return true;
  }
  bool u64(uint64_t &x) {
    std::span<const std::byte> a;
    if (!raw(8, a))
      return false;
    x = 0;
    for (auto q : a)
      x = (x << 8) | std::to_integer<uint64_t>(q);
    return true;
  }
  bool text(std::string_view &x) {
    uint16_t z;
    std::span<const std::byte> a;
    if (!u16(z) || z == 0 || !raw(z, a))
      return false;
    x = {reinterpret_cast<const char *>(a.data()), a.size()};
    return x.find('\0') == std::string_view::npos;
  }
};
bool magic(R &r, const auto &m) {
  std::span<const std::byte> x;
  return r.raw(m.size(), x) && std::ranges::equal(x, m);
}
bool ident(W &w, const Registration &r) {
  return w.u32(r.protocol_version) && w.text(r.service_id.view()) &&
         w.text(r.adapter.adapter_class.view()) &&
         w.text(r.adapter.implementation_digest.view()) &&
         w.u32(r.adapter.abi_version);
}
bool nonce(std::span<std::byte, kNonceBytes> x) {
  size_t n = 0;
  while (n < x.size()) {
    auto z = getrandom(x.data() + n, x.size() - n, 0);
    if (z < 0 && errno == EINTR)
      continue;
    if (z <= 0)
      return false;
    n += z;
  }
  return std::ranges::any_of(x, [](auto b) { return b != std::byte{}; });
}
int open_verified(const Registration &v) {
  if (v.service_id.view().empty() || v.adapter.abi_version == 0 ||
      v.protocol_version != 2 || !v.executable.is_absolute() ||
      v.executable.filename() == "sh" || v.executable.filename() == "bash" ||
      v.executable_digest.size() != 64)
    return -1;
  int fd = open(v.executable.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  struct stat s {};
  if (fd < 0 || fstat(fd, &s) || !S_ISREG(s.st_mode) ||
      uint32_t(s.st_uid) != v.expected_uid ||
      (s.st_mode & (S_IWGRP | S_IWOTH | S_ISUID | S_ISGID)) ||
      (s.st_mode & 0111) == 0 || s.st_size <= 0 ||
      s.st_size > 64 * 1024 * 1024) {
    if (fd >= 0)
      close(fd);
    return -1;
  }
  std::string b(static_cast<std::size_t>(s.st_size), '\0');
  std::size_t offset = 0;
  while (offset < b.size()) {
    const ssize_t count = read(fd, b.data() + offset, b.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0) {
      close(fd);
      return -1;
    }
    offset += static_cast<std::size_t>(count);
  }
  if (Digest(manifest::sha256_hex(b)) != v.executable_digest ||
      lseek(fd, 0, SEEK_SET) < 0) {
    close(fd);
    return -1;
  }
  return fd;
}
} // namespace
bool valid_registration(const Registration &v) {
  const int fd = open_verified(v);
  if (fd < 0)
    return false;
  close(fd);
  return true;
}
bool encode_handshake(const Registration &r,
                      std::span<const std::byte, kNonceBytes> n,
                      std::span<std::byte> o, size_t &w) {
  w = 0;
  W x{o};
  if (!x.raw(hs) || !ident(x, r) || !x.raw(n))
    return false;
  w = x.n;
  return true;
}
bool verify_handshake_echo(const Registration &r,
                           std::span<const std::byte, kNonceBytes> n,
                           std::span<const std::byte> i) {
  std::array<std::byte, kMaximumFrameBytes> x{};
  size_t z = 0;
  return encode_handshake(r, n, x, z) && i.size() == z &&
         std::ranges::equal(i, std::span(x).first(z));
}
bool encode_request(const RequestFrame &q, std::span<std::byte> o, size_t &w) {
  w = 0;
  if (!q.correlation || !q.authorization.grant_epoch ||
      q.payload.size() > definitions::kMaximumDynamicPayloadBytes)
    return false;
  W x{o};
  auto &a = q.authorization;
  if (!x.raw(rq) || !x.u32(2) || !x.text(q.service_id.view()) ||
      !x.text(q.adapter.adapter_class.view()) ||
      !x.text(q.adapter.implementation_digest.view()) ||
      !x.u32(q.adapter.abi_version) || !x.text(a.binding.plugin.view()) ||
      !x.text(a.binding.revision.view()) ||
      !x.text(a.binding.policy_fingerprint.view()) ||
      !x.u64(a.binding.generation) ||
      !x.text(a.definition.canonical_name.view()) ||
      !x.u32(a.definition.definition_generation) ||
      !x.text(a.definition.definition_digest.view()) || !x.u64(a.grant_epoch) ||
      !x.text(q.operation.view()) || !x.text(q.demand_scope.view()) ||
      !x.u64(q.correlation) || !x.raw(q.host_nonce) ||
      !x.u32(q.payload.size()) || !x.raw(q.payload))
    return false;
  w = x.n;
  return true;
}
bool decode_request(std::span<const std::byte> i, RequestFrame &q) {
  q = {};
  if (i.size() > kMaximumFrameBytes)
    return false;
  R r{i};
  uint32_t v, abi, dg, ps;
  std::string_view sid, ac, ad, p, rev, pol, dn, dd, op, sc;
  std::span<const std::byte> nn, pl;
  try {
    auto &a = q.authorization;
    if (!magic(r, rq) || !r.u32(v) || v != 2 || !r.text(sid) || !r.text(ac) ||
        !r.text(ad) || !r.u32(abi) || !abi || !r.text(p) || !r.text(rev) ||
        !r.text(pol) || !r.u64(a.binding.generation) || !r.text(dn) ||
        !r.u32(dg) || !dg || !r.text(dd) || !r.u64(a.grant_epoch) ||
        !a.grant_epoch || !r.text(op) || !r.text(sc) || !r.u64(q.correlation) ||
        !q.correlation || !r.raw(kNonceBytes, nn) || !r.u32(ps) ||
        ps > definitions::kMaximumDynamicPayloadBytes || !r.raw(ps, pl) ||
        r.n != i.size())
      return false;
    q.service_id = definitions::Name(sid);
    q.adapter = {definitions::Name(ac), Digest(ad), abi};
    a.binding = {permissions::PluginId(p), Digest(rev), Digest(pol),
                 a.binding.generation};
    a.definition = {definitions::Name(dn), dg, Digest(dd)};
    q.operation = definitions::Name(op);
    q.demand_scope = definitions::CanonicalScope(sc);
    std::ranges::copy(nn, q.host_nonce.begin());
    q.payload = pl;
  } catch (...) {
    return false;
  }
  return true;
}
bool encode_reply(const ReplyFrame &q, std::span<std::byte> o, size_t &w) {
  w = 0;
  if (!q.correlation ||
      q.payload.size() > definitions::kMaximumDynamicPayloadBytes)
    return false;
  W x{o};
  if (!x.raw(rp) || !x.u32(2) || !x.u64(q.correlation) ||
      !x.raw(q.host_nonce) || !x.u32(q.payload.size()) || !x.raw(q.payload))
    return false;
  w = x.n;
  return true;
}
bool decode_reply(std::span<const std::byte> i, ReplyFrame &q) {
  q = {};
  R r{i};
  uint32_t v, z;
  std::span<const std::byte> n, p;
  if (i.size() > kMaximumFrameBytes || !magic(r, rp) || !r.u32(v) || v != 2 ||
      !r.u64(q.correlation) || !q.correlation || !r.raw(kNonceBytes, n) ||
      !r.u32(z) || z > definitions::kMaximumDynamicPayloadBytes ||
      !r.raw(z, p) || r.n != i.size())
    return false;
  std::ranges::copy(n, q.host_nonce.begin());
  q.payload = p;
  return true;
}
Result invoke(const Registration &r,
              const definitions::AuthorizedDynamicRequest &q,
              std::span<std::byte> out, size_t &w,
              std::chrono::milliseconds timeout, uint64_t epoch,
              uint64_t correlation) {
  w = 0;
  if (correlation == 0)
    return Result::malformed;
  const int executable_fd = open_verified(r);
  if (executable_fd < 0)
    return Result::invalid_registration;
  struct DescriptorGuard {
    int value;
    ~DescriptorGuard() { close(value); }
  } executable{executable_fd};
  if (!epoch || epoch != q.authorization.grant_epoch)
    return Result::revoked;
  auto production_launcher =
      r.launcher == nullptr
          ? std::optional<plugin_runtime::launcher::Supervisor>(
                plugin_runtime::launcher::Supervisor::production())
          : std::nullopt;
  auto &launcher = r.launcher == nullptr ? *production_launcher : *r.launcher;
  auto launched = launcher.launchProvider(
      {.service_id = std::string(r.service_id.view()),
       .executable_sha256 = std::string(r.executable_digest.view()),
       .generation = epoch,
       .executable_fd = executable_fd});
  if (!launched)
    return launched.failure == plugin_runtime::launcher::LaunchFailure::startup_timeout
               ? Result::timeout
               : Result::crashed;
  auto &provider = *launched.worker;
  auto fail = [&](Result x) {
    static_cast<void>(provider.terminate());
    return x;
  };
  std::array<std::byte, kNonceBytes> n{};
  std::array<std::byte, kMaximumFrameBytes> b{};
  size_t z;
  std::span<const std::byte> got;
  if (!nonce(n) || !encode_handshake(r, n, b, z) ||
      !provider.send(plugin_runtime::launcher::EndpointRole::control,
                     std::span(b).first(z))) {
    return fail(Result::crashed);
  }
  auto received = provider.receive(plugin_runtime::launcher::EndpointRole::control,
                                   kMaximumFrameBytes, timeout);
  if (!received)
    return fail(Result::timeout);
  got = received.payload;
  if (!verify_handshake_echo(r, n, got))
    return fail(Result::identity_mismatch);
  RequestFrame req{r.service_id,
                   r.adapter,
                   q.authorization,
                   definitions::Name(q.operation),
                   definitions::CanonicalScope(q.demand_scope),
                   q.payload,
                   correlation,
                   n};
  if (!encode_request(req, b, z) ||
      !provider.send(plugin_runtime::launcher::EndpointRole::control,
                     std::span(b).first(z))) {
    return fail(Result::crashed);
  }
  received = provider.receive(plugin_runtime::launcher::EndpointRole::control,
                              kMaximumFrameBytes, timeout);
  if (!received)
    return fail(Result::timeout);
  got = received.payload;
  ReplyFrame reply;
  if (!decode_reply(got, reply) || reply.correlation != correlation ||
      reply.host_nonce != n || reply.payload.size() > out.size())
    return fail(Result::malformed);
  std::ranges::copy(reply.payload, out.begin());
  w = reply.payload.size();
  return provider.terminate() ? Result::completed : Result::crashed;
}

Result invoke_audited(const Registration &registration,
                      const definitions::AuthorizedDynamicRequest &request,
                      std::span<std::byte> output, std::size_t &written,
                      std::chrono::milliseconds timeout,
                      std::uint64_t current_epoch,
                      const InvocationGuard &guard) {
  written = 0;
  if (guard.audit == nullptr || guard.correlation == 0 ||
      guard.still_authorized == nullptr)
    return Result::audit_failed;
  const auto draft = [&](permissions::AuditEvent event,
                         permissions::AuditOutcome outcome) {
    permissions::AuditDraft value{
        .event = event,
        .outcome = outcome,
        .plugin = request.authorization.binding.plugin,
        .revision = request.authorization.binding.revision,
        .generation = request.authorization.binding.generation,
        .correlation = guard.correlation,
        .dynamic_operation =
            permissions::DynamicAuditIdentity{
                .capability = permissions::CapabilityId(
                    request.authorization.definition.canonical_name.view()),
                .definition_generation =
                    request.authorization.definition.definition_generation,
                .definition_digest =
                    request.authorization.definition.definition_digest,
                .operation = permissions::BoundedString<128>(request.operation),
                .grant_epoch = request.authorization.grant_epoch},
        .operation = std::nullopt,
        .capability = std::nullopt,
        .decision = outcome == permissions::AuditOutcome::allowed
                        ? permissions::GrantDecisionCode::allowed
                        : permissions::GrantDecisionCode::revoked,
        .metadata = {}};
    return value;
  };
  if (!guard.still_authorized(request.authorization,
                              guard.authorization_context))
    return Result::revoked;
  if (!guard.audit
           ->append(permissions::AuditProducer::broker,
                    draft(permissions::AuditEvent::operation_decided,
                          permissions::AuditOutcome::allowed))
           .status.ok())
    return Result::audit_failed;
  const auto result = invoke(registration, request, output, written, timeout,
                             current_epoch, guard.correlation);
  if (result == Result::completed &&
      !guard.still_authorized(request.authorization,
                              guard.authorization_context)) {
    written = 0;
    if (!guard.audit
             ->append(permissions::AuditProducer::broker,
                      draft(permissions::AuditEvent::operation_completed,
                            permissions::AuditOutcome::cancelled))
             .status.ok())
      return Result::audit_failed;
    return Result::revoked;
  }
  const auto outcome = result == Result::completed
                           ? permissions::AuditOutcome::allowed
                           : permissions::AuditOutcome::failed;
  if (!guard.audit
           ->append(
               permissions::AuditProducer::broker,
               draft(permissions::AuditEvent::operation_completed, outcome))
           .status.ok()) {
    written = 0;
    return Result::audit_failed;
  }
  return result;
}
} // namespace omarchy::plugins::external_provider
