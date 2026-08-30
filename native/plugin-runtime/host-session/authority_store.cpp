#include "authority_store.hpp"

#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <charconv>
#include <cerrno>
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <type_traits>
#include <unistd.h>
#include <vector>

namespace omarchy::plugin_runtime::host_session {
namespace {
constexpr std::size_t kMaximumFileBytes = 8 * 1024 * 1024;
constexpr std::size_t kMaximumDynamicGrants = 128;
constexpr std::string_view kLockName = ".authority.lock";
constexpr std::string_view kSlotsName = "slots";
constexpr std::array<std::byte, 8> kSnapshotMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'G'}, std::byte{'R'},
    std::byte{'A'}, std::byte{'N'}, std::byte{'T'}, std::byte{1}};
constexpr std::array<std::byte, 8> kSlotsMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'S'}, std::byte{'L'},
    std::byte{'O'}, std::byte{'T'}, std::byte{'S'}, std::byte{1}};
std::atomic<std::uint64_t> temporary_sequence{1};

struct Writer {
  std::vector<std::byte> bytes;

  bool raw(std::span<const std::byte> value) {
    if (value.size() > kMaximumFileBytes - bytes.size())
      return false;
    bytes.insert(bytes.end(), value.begin(), value.end());
    return true;
  }
  bool u8(std::uint8_t value) { return raw(std::array{std::byte{value}}); }
  bool u16(std::uint16_t value) {
    return raw(std::array{std::byte{static_cast<unsigned char>(value >> 8)},
                          std::byte{static_cast<unsigned char>(value)}});
  }
  bool u32(std::uint32_t value) {
    std::array<std::byte, 4> bytes{};
    for (int index = 0; index < 4; ++index)
      bytes[index] = std::byte{static_cast<unsigned char>(value >> (24 - 8 * index))};
    return raw(bytes);
  }
  bool u64(std::uint64_t value) {
    std::array<std::byte, 8> bytes{};
    for (int index = 0; index < 8; ++index)
      bytes[index] = std::byte{static_cast<unsigned char>(value >> (56 - 8 * index))};
    return raw(bytes);
  }
  bool text(std::string_view value) {
    return !value.empty() && value.size() <= UINT16_MAX &&
           u16(static_cast<std::uint16_t>(value.size())) &&
           raw(std::as_bytes(std::span(value.data(), value.size())));
  }
  bool blob(std::string_view value) {
    return value.size() <= UINT16_MAX &&
           u16(static_cast<std::uint16_t>(value.size())) &&
           raw(std::as_bytes(std::span(value.data(), value.size())));
  }
};

struct Reader {
  std::span<const std::byte> bytes;
  std::size_t offset = 0;

  bool raw(std::size_t size, std::span<const std::byte> &value) {
    if (size > bytes.size() - std::min(offset, bytes.size()))
      return false;
    value = bytes.subspan(offset, size);
    offset += size;
    return true;
  }
  bool u8(std::uint8_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(1, bytes))
      return false;
    value = std::to_integer<std::uint8_t>(bytes[0]);
    return true;
  }
  bool u16(std::uint16_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(2, bytes))
      return false;
    value = static_cast<std::uint16_t>(std::to_integer<unsigned>(bytes[0]) << 8 |
                                       std::to_integer<unsigned>(bytes[1]));
    return true;
  }
  bool u32(std::uint32_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(4, bytes))
      return false;
    value = 0;
    for (const auto byte : bytes)
      value = value << 8 | std::to_integer<unsigned>(byte);
    return true;
  }
  bool u64(std::uint64_t &value) {
    std::span<const std::byte> bytes;
    if (!raw(8, bytes))
      return false;
    value = 0;
    for (const auto byte : bytes)
      value = value << 8 | std::to_integer<unsigned>(byte);
    return true;
  }
  bool text(std::string_view &value) {
    std::uint16_t size = 0;
    std::span<const std::byte> bytes;
    if (!u16(size) || size == 0 || !raw(size, bytes))
      return false;
    value = {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
    return value.find('\0') == std::string_view::npos;
  }
  bool blob(std::string_view &value) {
    std::uint16_t size = 0;
    std::span<const std::byte> bytes;
    if (!u16(size) || !raw(size, bytes))
      return false;
    value = {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
    return true;
  }
};

bool encode_snapshot(const policy::GrantSnapshot &snapshot,
                     std::vector<std::byte> &output) {
  Writer writer;
  if (!writer.raw(kSnapshotMagic) ||
      !writer.text(snapshot.binding.plugin.view()) ||
      !writer.text(snapshot.binding.revision.view()) ||
      !writer.text(snapshot.binding.policy_fingerprint.view()) ||
      !writer.u64(snapshot.binding.generation) ||
      !writer.text(snapshot.source_request_fingerprint.view()) ||
      !writer.u8(static_cast<std::uint8_t>(snapshot.requests.size())))
    return false;
  for (const auto &request : snapshot.requests.values()) {
    if (!writer.text(request.capability.id.view()) ||
        !writer.u16(request.capability.version) ||
        !writer.blob(permissions::canonical_scope(request.scope)) ||
        !writer.u8(request.required))
      return false;
  }
  if (!writer.u8(static_cast<std::uint8_t>(snapshot.grants.size())))
    return false;
  for (const auto &grant : snapshot.grants.values()) {
    if (!writer.text(grant.capability.id.view()) ||
        !writer.u16(grant.capability.version) ||
        !writer.blob(permissions::canonical_scope(grant.scope)) ||
        !writer.u8(static_cast<std::uint8_t>(grant.state)) ||
        !writer.u64(grant.epoch))
      return false;
  }
  if (snapshot.dynamic_grants.size() > kMaximumDynamicGrants ||
      !writer.u8(static_cast<std::uint8_t>(snapshot.dynamic_grants.size())))
    return false;
  std::array<std::byte, definitions::kMaximumDynamicEnvelopeBytes> encoded{};
  for (const auto &grant : snapshot.dynamic_grants) {
    std::size_t size = 0;
    if (!definitions::encode_dynamic_grant(grant, encoded, size) ||
        size > definitions::kMaximumDynamicEnvelopeBytes ||
        !writer.u32(static_cast<std::uint32_t>(size)) ||
        !writer.raw(std::span(encoded).first(size)))
      return false;
  }
  output = std::move(writer.bytes);
  return true;
}

bool decode_snapshot(std::span<const std::byte> bytes,
                     policy::GrantSnapshot &snapshot) {
  Reader reader{bytes};
  std::span<const std::byte> magic;
  std::string_view text;
  std::uint8_t count = 0;
  snapshot = {};
  try {
    if (!reader.raw(kSnapshotMagic.size(), magic) ||
        !std::ranges::equal(magic, kSnapshotMagic) || !reader.text(text))
      return false;
    snapshot.binding.plugin = permissions::PluginId(text);
    if (!reader.text(text)) return false;
    snapshot.binding.revision = permissions::Digest(text);
    if (!reader.text(text)) return false;
    snapshot.binding.policy_fingerprint = permissions::Digest(text);
    if (!reader.u64(snapshot.binding.generation) || !reader.text(text)) return false;
    snapshot.source_request_fingerprint = permissions::Digest(text);
    if (!reader.u8(count) || count > 64) return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      permissions::CapabilityRequest request;
      std::uint8_t required = 0;
      if (!reader.text(text)) return false;
      request.capability.id = permissions::CapabilityId(text);
      if (!reader.u16(request.capability.version) || !reader.blob(text))
        return false;
      request.scope =
          permissions::scope_from_canonical(request.capability, text);
      if (!reader.u8(required) || required > 1)
        return false;
      request.required = required;
      snapshot.requests.push_back(std::move(request));
    }
    if (!reader.u8(count) || count > 64) return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      permissions::GrantRecord grant;
      std::uint8_t state = 0;
      if (!reader.text(text)) return false;
      grant.capability.id = permissions::CapabilityId(text);
      if (!reader.u16(grant.capability.version) || !reader.blob(text))
        return false;
      grant.scope = permissions::scope_from_canonical(grant.capability, text);
      if (!reader.u8(state) ||
          state > static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !reader.u64(grant.epoch))
        return false;
      grant.state = static_cast<permissions::GrantState>(state);
      snapshot.grants.push_back(std::move(grant));
    }
    if (!reader.u8(count) || count > kMaximumDynamicGrants) return false;
    for (std::uint8_t index = 0; index < count; ++index) {
      std::uint32_t size = 0;
      std::span<const std::byte> encoded;
      definitions::DynamicRevisionGrant grant;
      if (!reader.u32(size) ||
          size > definitions::kMaximumDynamicEnvelopeBytes ||
          !reader.raw(size, encoded) ||
          !definitions::decode_dynamic_grant(encoded, grant))
        return false;
      snapshot.dynamic_grants.push_back(std::move(grant));
    }
  } catch (...) {
    return false;
  }
  return reader.offset == bytes.size();
}

bool same_requests(const permissions::RequestSet &left,
                   const permissions::RequestSet &right) {
  return std::ranges::equal(left.values(), right.values());
}

bool complete_snapshot(const VerifiedRevision &verified,
                       const policy::GrantSnapshot &snapshot,
                       const definitions::TrustedDefinitionRegistry &registry,
                       definitions::DynamicScopeValidator validator) {
  try {
    if (snapshot.binding.plugin.view() != verified.manifest.id ||
        snapshot.binding.revision.view() != verified.tree_sha256 ||
        snapshot.source_request_fingerprint.view() != verified.request_sha256 ||
        verified.request_sha256 != plugins::manifest::requested_capability_fingerprint(
                                       verified.manifest.requests) ||
        snapshot.binding.generation == 0 ||
        snapshot.binding.policy_fingerprint.view() !=
            permissions::policy_request_fingerprint(snapshot.requests) ||
        !same_requests(snapshot.requests,
                       permissions::requests_from_manifest(verified.manifest)))
      return false;
    if (snapshot.grants.size() != snapshot.requests.size())
      return false;
    permissions::PermissionAuthority builtin(snapshot.binding, snapshot.requests,
                                               snapshot.grants);
    (void)builtin;
    std::vector<definitions::DynamicRequest> requested;
    for (const auto &manifest_request : verified.manifest.requests) {
      if (manifest_request.definition_generation == 0)
        continue;
      auto dynamic =
          definitions::dynamic_request_from_manifest(manifest_request, registry);
      if (!dynamic)
        return false;
      requested.push_back(std::move(*dynamic));
    }
    if (requested.size() != snapshot.dynamic_grants.size() ||
        requested.size() > kMaximumDynamicGrants)
      return false;
    std::ranges::sort(requested, {}, [](const auto &request) {
      return request.definition.canonical_name;
    });
    for (std::size_t index = 0; index < requested.size(); ++index) {
      const auto &grant = snapshot.dynamic_grants[index];
      if (grant.binding != snapshot.binding || grant.request != requested[index] ||
          static_cast<std::uint8_t>(grant.grant.state) >
              static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !definitions::review_dynamic_grant(registry, grant, validator))
        return false;
      if (index > 0 &&
          !(snapshot.dynamic_grants[index - 1].request.definition.canonical_name <
            grant.request.definition.canonical_name))
        return false;
    }
    return true;
  } catch (...) {
    return false;
  }
}

AuthorityRevisionRef reference_for(const policy::GrantSnapshot &snapshot,
                                   std::string_view digest) {
  return {.snapshot_digest = permissions::Digest(digest),
          .generation = snapshot.binding.generation};
}

bool write_reference(Writer &writer,
                     const std::optional<AuthorityRevisionRef> &reference) {
  if (!writer.u8(reference.has_value()))
    return false;
  return !reference ||
         (writer.text(reference->snapshot_digest.view()) &&
          writer.u64(reference->generation));
}

bool read_reference(Reader &reader,
                    std::optional<AuthorityRevisionRef> &reference) {
  std::uint8_t present = 0;
  std::string_view text;
  if (!reader.u8(present) || present > 1)
    return false;
  if (!present) {
    reference.reset();
    return true;
  }
  try {
    AuthorityRevisionRef value;
    if (!reader.text(text)) return false;
    value.snapshot_digest = permissions::Digest(text);
    if (!reader.u64(value.generation) || value.generation == 0) return false;
    reference = std::move(value);
    return true;
  } catch (...) {
    return false;
  }
}

std::vector<std::byte> encode_slots(const AuthoritySlots &slots) {
  Writer writer;
  if (!writer.raw(kSlotsMagic) || !writer.u64(slots.sequence) ||
      !writer.u64(slots.generation_high_watermark) ||
      !write_reference(writer, slots.active) ||
      !write_reference(writer, slots.candidate))
    return {};
  return std::move(writer.bytes);
}

std::optional<AuthoritySlots> decode_slots(std::span<const std::byte> bytes) {
  Reader reader{bytes};
  std::span<const std::byte> magic;
  AuthoritySlots slots;
  if (!reader.raw(kSlotsMagic.size(), magic) ||
      !std::ranges::equal(magic, kSlotsMagic) || !reader.u64(slots.sequence) ||
      !reader.u64(slots.generation_high_watermark) ||
      !read_reference(reader, slots.active) ||
      !read_reference(reader, slots.candidate) || reader.offset != bytes.size())
    return std::nullopt;
  return slots;
}

bool trusted_directory(const struct stat &metadata, std::uint32_t uid) {
  return S_ISDIR(metadata.st_mode) && metadata.st_uid == uid &&
         (metadata.st_mode & 0777) == 0700;
}

bool trusted_file(const struct stat &metadata, std::uint32_t uid) {
  return S_ISREG(metadata.st_mode) && metadata.st_uid == uid &&
         metadata.st_nlink == 1 && (metadata.st_mode & 0777) == 0600;
}

bool secure_created_file(int descriptor, std::uint32_t uid) {
  struct stat metadata {};
  return ::fchmod(descriptor, 0600) == 0 &&
         ::fstat(descriptor, &metadata) == 0 && trusted_file(metadata, uid);
}

std::optional<std::vector<std::byte>>
read_file(int root_fd, std::string_view name, std::uint32_t uid,
          bool missing_is_empty = false) {
  const std::string owned_name(name);
  OwnedDescriptor file(
      ::openat(root_fd, owned_name.c_str(),
               O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK));
  if (!file)
    return missing_is_empty && errno == ENOENT
               ? std::optional(std::vector<std::byte>{})
               : std::nullopt;
  struct stat before {}, after {};
  if (::fstat(file.get(), &before) < 0 || !trusted_file(before, uid) ||
      before.st_size < 0 ||
      static_cast<std::uint64_t>(before.st_size) > kMaximumFileBytes)
    return std::nullopt;
  std::vector<std::byte> bytes(static_cast<std::size_t>(before.st_size));
  std::size_t offset = 0;
  while (offset < bytes.size()) {
    const auto count = ::read(file.get(), bytes.data() + offset,
                              bytes.size() - offset);
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return std::nullopt;
    offset += static_cast<std::size_t>(count);
  }
  std::byte trailing{};
  if (::read(file.get(), &trailing, 1) != 0)
    return std::nullopt;
  if (::fstat(file.get(), &after) < 0 || before.st_dev != after.st_dev ||
      before.st_ino != after.st_ino || before.st_size != after.st_size ||
      before.st_mtim.tv_sec != after.st_mtim.tv_sec ||
      before.st_mtim.tv_nsec != after.st_mtim.tv_nsec)
    return std::nullopt;
  return bytes;
}

bool write_all(int descriptor, std::span<const std::byte> bytes) {
  while (!bytes.empty()) {
    const auto count = ::write(descriptor, bytes.data(), bytes.size());
    if (count < 0 && errno == EINTR)
      continue;
    if (count <= 0)
      return false;
    bytes = bytes.subspan(static_cast<std::size_t>(count));
  }
  return true;
}

std::string temporary_name(std::string_view role) {
  return "." + std::string(role) + "." + std::to_string(::getpid()) + "." +
         std::to_string(temporary_sequence.fetch_add(1));
}

std::string digest(std::span<const std::byte> bytes) {
  return plugins::manifest::sha256_hex(bytes);
}

std::string record_name(const AuthorityRevisionRef &reference) {
  return "grant-" + std::string(reference.snapshot_digest.view());
}

std::optional<AuthoritySlots> read_slots_unlocked(int root_fd,
                                                  std::uint32_t uid) {
  struct stat metadata {};
  if (::fstatat(root_fd, std::string(kSlotsName).c_str(), &metadata,
                AT_SYMLINK_NOFOLLOW) < 0) {
    if (errno == ENOENT)
      return AuthoritySlots{};
    return std::nullopt;
  }
  auto bytes = read_file(root_fd, kSlotsName, uid);
  if (!bytes)
    return std::nullopt;
  return decode_slots(*bytes);
}

bool canonical_digest(const permissions::Digest &value) {
  return value.size() == 64 && std::ranges::all_of(value.view(), [](char byte) {
           return (byte >= '0' && byte <= '9') ||
                  (byte >= 'a' && byte <= 'f');
         });
}

bool valid_slots(const AuthoritySlots &slots) {
  if (slots.sequence < slots.generation_high_watermark)
    return false;
  for (const auto *reference : {&slots.active, &slots.candidate}) {
    if (!*reference)
      continue;
    if (!canonical_digest((*reference)->snapshot_digest) ||
        (*reference)->generation == 0 ||
        (*reference)->generation > slots.generation_high_watermark)
      return false;
  }
  if (slots.candidate &&
      slots.candidate->generation != slots.generation_high_watermark)
    return false;
  if (slots.active && slots.candidate &&
      slots.active->generation >= slots.candidate->generation)
    return false;
  return true;
}

void cleanup_unreferenced(int root_fd, const AuthoritySlots &before,
                          const AuthoritySlots &after) {
  const auto retained = [&after](const AuthorityRevisionRef &reference) {
    return (after.active &&
            after.active->snapshot_digest == reference.snapshot_digest) ||
           (after.candidate &&
            after.candidate->snapshot_digest == reference.snapshot_digest);
  };
  std::optional<permissions::Digest> removed;
  for (const auto *reference : {&before.active, &before.candidate}) {
    if (!*reference || retained(**reference) ||
        (removed && *removed == (*reference)->snapshot_digest))
      continue;
    if (::unlinkat(root_fd, record_name(**reference).c_str(), 0) == 0)
      removed = (*reference)->snapshot_digest;
  }
  if (removed)
    (void)::fsync(root_fd);
}

std::optional<policy::GrantSnapshot> load_snapshot(
    int root_fd, std::uint32_t uid, const AuthorityRevisionRef &reference) {
  auto bytes = read_file(root_fd, record_name(reference), uid);
  if (!bytes || digest(*bytes) != reference.snapshot_digest.view())
    return std::nullopt;
  policy::GrantSnapshot snapshot;
  std::vector<std::byte> canonical;
  if (!decode_snapshot(*bytes, snapshot) || !encode_snapshot(snapshot, canonical) ||
      canonical != *bytes ||
      snapshot.binding.generation != reference.generation)
    return std::nullopt;
  try {
    permissions::PermissionAuthority builtin(snapshot.binding, snapshot.requests,
                                               snapshot.grants);
    (void)builtin;
    if (permissions::policy_request_fingerprint(snapshot.requests) !=
        snapshot.binding.policy_fingerprint.view())
      return std::nullopt;
    definitions::Name previous;
    bool have_previous = false;
    for (const auto &dynamic : snapshot.dynamic_grants) {
      if (dynamic.binding != snapshot.binding ||
          dynamic.request.definition != dynamic.grant.definition ||
          dynamic.grant.epoch == 0 ||
          static_cast<std::uint8_t>(dynamic.grant.state) >
              static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
          !std::ranges::all_of(dynamic.grant.operations.values(),
                              [&](const auto &operation) {
                                return dynamic.request.operations.contains(operation);
                              }) ||
          (have_previous &&
           !(previous < dynamic.request.definition.canonical_name)))
        return std::nullopt;
      previous = dynamic.request.definition.canonical_name;
      have_previous = true;
    }
  } catch (...) {
    return std::nullopt;
  }
  return snapshot;
}

AuthorityMutationResult store_snapshot_record(
    int root_fd, std::uint32_t expected_uid,
    const policy::GrantSnapshot &snapshot, AuthorityRevisionRef &reference) {
  std::vector<std::byte> bytes;
  if (!encode_snapshot(snapshot, bytes))
    return AuthorityMutationResult::invalid;
  const auto hash = digest(bytes);
  reference = reference_for(snapshot, hash);
  const auto name = record_name(reference);
  const auto temporary = temporary_name("grant");
  OwnedDescriptor file(::openat(root_fd, temporary.c_str(),
                                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                                    O_NOFOLLOW,
                                0600));
  if (!file || !secure_created_file(file.get(), expected_uid) ||
      !write_all(file.get(), bytes) || ::fsync(file.get()) < 0) {
    ::unlinkat(root_fd, temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  if (::syscall(SYS_renameat2, root_fd, temporary.c_str(), root_fd,
                name.c_str(), RENAME_NOREPLACE) < 0) {
    if (errno != EEXIST) {
      ::unlinkat(root_fd, temporary.c_str(), 0);
      return AuthorityMutationResult::io_error;
    }
    auto existing = read_file(root_fd, name, expected_uid);
    if (!existing || *existing != bytes ||
        ::unlinkat(root_fd, temporary.c_str(), 0) < 0) {
      ::unlinkat(root_fd, temporary.c_str(), 0);
      return AuthorityMutationResult::io_error;
    }
  }
  return ::fsync(root_fd) == 0 ? AuthorityMutationResult::applied
                               : AuthorityMutationResult::io_error;
}

bool activatable(const policy::GrantSnapshot &snapshot) {
  for (const auto &request : snapshot.requests.values()) {
    if (!request.required)
      continue;
    const auto granted = std::ranges::find_if(
        snapshot.grants.values(), [&](const auto &grant) {
          return grant.capability == request.capability &&
                 grant.state == permissions::GrantState::granted;
        });
    if (granted == snapshot.grants.values().end())
      return false;
  }
  return std::ranges::all_of(snapshot.dynamic_grants, [](const auto &dynamic) {
    return !dynamic.request.required ||
           dynamic.grant.state == permissions::GrantState::granted;
  });
}
} // namespace

AuthorityStore::AuthorityStore(
    OwnedDescriptor root, OwnedDescriptor lock, std::uint32_t expected_uid,
    permissions::PluginId expected_plugin)
    : root_(std::move(root)), lock_(std::move(lock)),
      expected_uid_(expected_uid), expected_plugin_(std::move(expected_plugin)),
      owner_pid_(::getpid()) {}

AuthorityStore::~AuthorityStore() {
  std::scoped_lock lock(mutation_mutex_);
  if (auto live = bound_live_.lock())
    live->revoke();
}

std::unique_ptr<AuthorityStore> AuthorityStore::open(
    int root_directory_fd, std::uint32_t expected_uid,
    permissions::PluginId expected_plugin) {
  OwnedDescriptor root(::fcntl(root_directory_fd, F_DUPFD_CLOEXEC, 0));
  struct stat metadata {};
  if (!root || ::fstat(root.get(), &metadata) < 0 ||
      !trusted_directory(metadata, expected_uid))
    return nullptr;
  int lock_fd = ::openat(root.get(), std::string(kLockName).c_str(),
                         O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW |
                             O_NONBLOCK,
                         0600);
  if (lock_fd >= 0) {
    if (!secure_created_file(lock_fd, expected_uid)) {
      ::close(lock_fd);
      return nullptr;
    }
  } else if (errno == EEXIST) {
    lock_fd = ::openat(root.get(), std::string(kLockName).c_str(),
                       O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
  }
  OwnedDescriptor lock(lock_fd);
  if (!lock || ::fstat(lock.get(), &metadata) < 0 ||
      !trusted_file(metadata, expected_uid) ||
      ::flock(lock.get(), LOCK_EX | LOCK_NB) < 0)
    return nullptr;
  return std::unique_ptr<AuthorityStore>(new AuthorityStore(
      std::move(root), std::move(lock), expected_uid,
      std::move(expected_plugin)));
}

std::optional<AuthoritySlots> AuthorityStore::read_slots() const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_)
    return std::nullopt;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return std::nullopt;
  return slots;
}

std::optional<AuthorityView> AuthorityStore::read_authority_view() const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_)
    return std::nullopt;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return std::nullopt;
  std::optional<policy::GrantSnapshot> active;
  if (slots->active) {
    active = load_snapshot(root_.get(), expected_uid_, *slots->active);
    if (!active || active->binding.plugin != expected_plugin_)
      return std::nullopt;
  }
  return AuthorityView{.authority_slots = *slots, .active = std::move(active)};
}

std::optional<FilesystemIdentity> AuthorityStore::root_identity() const {
  std::scoped_lock lock(mutation_mutex_);
  struct stat metadata {};
  if (::getpid() != owner_pid_ || ::fstat(root_.get(), &metadata) < 0)
    return std::nullopt;
  return FilesystemIdentity{.device = static_cast<std::uint64_t>(metadata.st_dev),
                            .inode = static_cast<std::uint64_t>(metadata.st_ino)};
}

bool AuthorityStore::bind_live_activation(
    const permissions::ActivationBinding &binding,
    const std::shared_ptr<LiveGenerationState> &live) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_ || !live ||
      !live->current(binding))
    return false;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || !slots->active ||
      slots->active->generation != binding.generation)
    return false;
  auto active = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!active || active->binding != binding || !activatable(*active))
    return false;
  if (auto previous = bound_live_.lock(); previous == live)
    return true;
  else if (previous)
    previous->revoke();
  bound_live_ = live;
  return true;
}

AuthorityMutationResult AuthorityStore::replace_slots(AuthoritySlots slots) {
  const auto bytes = encode_slots(slots);
  if (bytes.empty())
    return AuthorityMutationResult::invalid;
  const auto temporary = temporary_name("slots");
  OwnedDescriptor file(::openat(root_.get(), temporary.c_str(),
                                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC |
                                    O_NOFOLLOW,
                                0600));
  if (!file || !secure_created_file(file.get(), expected_uid_) ||
      !write_all(file.get(), bytes) || ::fsync(file.get()) < 0 ||
      ::renameat(root_.get(), temporary.c_str(), root_.get(),
                 std::string(kSlotsName).c_str()) < 0 ||
      ::fsync(root_.get()) < 0) {
    ::unlinkat(root_.get(), temporary.c_str(), 0);
    return AuthorityMutationResult::io_error;
  }
  return AuthorityMutationResult::applied;
}

AuthorityMutationResult AuthorityStore::publish_candidate(
    const VerifiedRevision &verified, const policy::GrantSnapshot &snapshot,
    std::uint64_t expected_sequence,
    const definitions::TrustedDefinitionRegistry &definitions,
    definitions::DynamicScopeValidator scope_validator) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (poisoned_)
    return AuthorityMutationResult::poisoned;
  if (!complete_snapshot(verified, snapshot, definitions, scope_validator))
    return AuthorityMutationResult::invalid;
  if (snapshot.binding.plugin != expected_plugin_)
    return AuthorityMutationResult::invalid;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  if (slots->generation_high_watermark == UINT64_MAX ||
      snapshot.binding.generation != slots->generation_high_watermark + 1)
    return AuthorityMutationResult::invalid;
  const auto previous = *slots;

  AuthorityRevisionRef reference;
  const auto stored =
      store_snapshot_record(root_.get(), expected_uid_, snapshot, reference);
  if (stored != AuthorityMutationResult::applied)
    return stored;
  slots->candidate = reference;
  slots->generation_high_watermark = snapshot.binding.generation;
  ++slots->sequence;
  const auto result = replace_slots(*slots);
  if (result == AuthorityMutationResult::applied)
    cleanup_unreferenced(root_.get(), previous, *slots);
  return result;
}

AuthorityMutationResult AuthorityStore::promote_candidate(
    const permissions::ActivationBinding &candidate,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (poisoned_)
    return AuthorityMutationResult::poisoned;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (!slots->candidate)
    return AuthorityMutationResult::invalid;
  auto candidate_snapshot =
      load_snapshot(root_.get(), expected_uid_, *slots->candidate);
  if (!candidate_snapshot)
    return AuthorityMutationResult::invalid;
  if (candidate_snapshot->binding != candidate)
    return AuthorityMutationResult::invalid;
  if (!activatable(*candidate_snapshot))
    return AuthorityMutationResult::invalid;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  if (auto live = bound_live_.lock())
    live->revoke();
  bound_live_.reset();
  const auto previous = *slots;
  slots->active = std::move(slots->candidate);
  slots->candidate.reset();
  ++slots->sequence;
  const auto result = replace_slots(*slots);
  if (result == AuthorityMutationResult::applied)
    cleanup_unreferenced(root_.get(), previous, *slots);
  return result;
}

AuthorityMutationResult AuthorityStore::discard_candidate(
    const permissions::ActivationBinding &candidate,
    std::uint64_t expected_sequence) {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return AuthorityMutationResult::io_error;
  if (poisoned_)
    return AuthorityMutationResult::poisoned;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots))
    return AuthorityMutationResult::io_error;
  if (slots->sequence != expected_sequence)
    return AuthorityMutationResult::stale_sequence;
  if (!slots->candidate)
    return AuthorityMutationResult::invalid;
  auto candidate_snapshot =
      load_snapshot(root_.get(), expected_uid_, *slots->candidate);
  if (!candidate_snapshot || candidate_snapshot->binding != candidate)
    return AuthorityMutationResult::invalid;
  if (slots->sequence == UINT64_MAX)
    return AuthorityMutationResult::invalid;
  const auto previous = *slots;
  slots->candidate.reset();
  ++slots->sequence;
  const auto result = replace_slots(*slots);
  if (result == AuthorityMutationResult::applied)
    cleanup_unreferenced(root_.get(), previous, *slots);
  return result;
}

AuthorityRevocationResult AuthorityStore::revoke_active(
    const permissions::CapabilityKey &capability,
    std::uint64_t expected_sequence) {
  return revoke_active(&capability, nullptr, expected_sequence);
}

AuthorityRevocationResult AuthorityStore::revoke_active(
    const definitions::CapabilityReference &definition,
    std::uint64_t expected_sequence) {
  return revoke_active(nullptr, &definition, expected_sequence);
}

AuthorityRevocationResult AuthorityStore::revoke_active(
    const permissions::CapabilityKey *capability,
    const definitions::CapabilityReference *definition,
    std::uint64_t expected_sequence) {
  const auto failure = [](AuthorityMutationResult status) {
    return AuthorityRevocationResult{
        .status = status, .binding = std::nullopt, .activatable = false};
  };
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_)
    return failure(AuthorityMutationResult::io_error);
  if (poisoned_)
    return failure(AuthorityMutationResult::poisoned);
  if ((capability == nullptr) == (definition == nullptr))
    return failure(AuthorityMutationResult::invalid);

  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || !slots->active)
    return failure(AuthorityMutationResult::io_error);
  if (slots->sequence != expected_sequence)
    return failure(AuthorityMutationResult::stale_sequence);
  if (slots->sequence == UINT64_MAX ||
      slots->generation_high_watermark == UINT64_MAX)
    return failure(AuthorityMutationResult::invalid);
  auto active = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!active || active->binding.plugin != expected_plugin_)
    return failure(AuthorityMutationResult::io_error);

  bool found = false;
  if (capability != nullptr) {
    for (auto &grant : active->grants.values()) {
      if (grant.capability != *capability)
        continue;
      if (found || grant.state != permissions::GrantState::granted)
        return failure(AuthorityMutationResult::invalid);
      grant.state = permissions::GrantState::revoked;
      found = true;
    }
  } else {
    for (auto &dynamic : active->dynamic_grants) {
      if (dynamic.request.definition != *definition)
        continue;
      if (found || dynamic.grant.state != permissions::GrantState::granted)
        return failure(AuthorityMutationResult::invalid);
      dynamic.grant.state = permissions::GrantState::revoked;
      found = true;
    }
  }
  if (!found)
    return failure(AuthorityMutationResult::invalid);

  const auto next_generation = slots->generation_high_watermark + 1;
  active->binding.generation = next_generation;
  for (auto &grant : active->grants.values())
    grant.epoch = next_generation;
  for (auto &dynamic : active->dynamic_grants) {
    dynamic.binding = active->binding;
    dynamic.grant.epoch = next_generation;
  }

  if (auto live = bound_live_.lock())
    live->revoke();
  bound_live_.reset();
  // From this fence until a complete typed success result exists, every exit
  // leaves this process unable to reuse potentially ambiguous durable state.
  poisoned_ = true;
  try {
    AuthorityRevisionRef reference;
    const auto stored = store_snapshot_record(root_.get(), expected_uid_,
                                              *active, reference);
    if (stored != AuthorityMutationResult::applied)
      return failure(stored);

    const auto previous = *slots;
    slots->active = reference;
    slots->candidate.reset();
    slots->generation_high_watermark = next_generation;
    ++slots->sequence;
    const auto replaced = replace_slots(*slots);
    if (replaced != AuthorityMutationResult::applied)
      return failure(replaced);
    cleanup_unreferenced(root_.get(), previous, *slots);
    AuthorityRevocationResult success{
        .status = AuthorityMutationResult::applied,
        .binding = active->binding,
        .activatable = activatable(*active)};
    static_assert(
        std::is_nothrow_move_constructible_v<AuthorityRevocationResult>);
    poisoned_ = false;
    return success;
  } catch (...) {
    // Once the old live generation is fenced, no exceptional persistence path
    // may leave this in-process store usable against ambiguous durable state.
    return failure(AuthorityMutationResult::io_error);
  }
}

std::optional<policy::GrantSnapshot>
AuthorityStore::resolve(std::string_view plugin_id,
                        std::string_view revision_sha256) const {
  std::scoped_lock lock(mutation_mutex_);
  if (::getpid() != owner_pid_ || poisoned_)
    return std::nullopt;
  auto slots = read_slots_unlocked(root_.get(), expected_uid_);
  if (!slots || !valid_slots(*slots) || plugin_id != expected_plugin_.view() ||
      !slots->active)
    return std::nullopt;
  auto snapshot = load_snapshot(root_.get(), expected_uid_, *slots->active);
  if (!snapshot || snapshot->binding.plugin.view() != plugin_id ||
      snapshot->binding.revision.view() != revision_sha256 ||
      !activatable(*snapshot))
    return std::nullopt;
  return snapshot;
}

} // namespace omarchy::plugin_runtime::host_session
