#include "grant_store.hpp"

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <stdexcept>
#include <string>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>

namespace omarchy::plugins::grants {
namespace {

constexpr std::string_view kStoreFile = "grants-v1.bin";
constexpr std::string_view kLockFile = "grants-v1.lock";
constexpr std::array<std::byte, 8> kMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'G'}, std::byte{'R'},
    std::byte{'A'}, std::byte{'N'}, std::byte{'T'}, std::byte{0}};

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}

class FileDescriptor {
public:
  explicit FileDescriptor(int value = -1) : value_(value) {}
  ~FileDescriptor() {
    if (value_ >= 0)
      close(value_);
  }
  FileDescriptor(const FileDescriptor &) = delete;
  FileDescriptor &operator=(const FileDescriptor &) = delete;
  FileDescriptor(FileDescriptor &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  FileDescriptor &operator=(FileDescriptor &&other) noexcept {
    if (this != &other) {
      if (value_ >= 0)
        close(value_);
      value_ = std::exchange(other.value_, -1);
    }
    return *this;
  }
  [[nodiscard]] int get() const { return value_; }
  [[nodiscard]] explicit operator bool() const { return value_ >= 0; }

private:
  int value_;
};

std::string system_error(std::string_view action) {
  return std::string(action) + ": " + std::strerror(errno);
}

bool valid_digest(std::string_view value) {
  return value.size() == 64 &&
         std::ranges::all_of(value, [](unsigned char byte) {
           return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'f');
         });
}

bool same_binding(const permission::ActivationBinding &left,
                  const permission::ActivationBinding &right) {
  return left == right;
}

bool same_revision(const RevisionGrants &persisted,
                   const RevisionGrants &prospective) {
  return same_binding(persisted.binding, prospective.binding) &&
         persisted.source_request_fingerprint ==
             prospective.source_request_fingerprint;
}

void reject_source_alias(const std::optional<RevisionGrants> &persisted,
                         const RevisionGrants &prospective) {
  if (persisted && same_binding(persisted->binding, prospective.binding))
    require(
        persisted->source_request_fingerprint ==
            prospective.source_request_fingerprint,
        "source request fingerprint does not match persisted revision binding");
}

const permission::CapabilityRequest *
request_for(const permission::RequestSet &requests,
            const permission::CapabilityKey &capability) {
  const auto found =
      std::ranges::find_if(requests.values(), [&](const auto &item) {
        return item.capability == capability;
      });
  return found == requests.values().end() ? nullptr : &*found;
}

permission::GrantRecord *
grant_for(permission::GrantSet &grants,
          const permission::CapabilityKey &capability) {
  const auto found =
      std::ranges::find_if(grants.values(), [&](const auto &item) {
        return item.capability == capability;
      });
  return found == grants.values().end() ? nullptr : &*found;
}

const permission::GrantRecord *
grant_for(const permission::GrantSet &grants,
          const permission::CapabilityKey &capability) {
  const auto found =
      std::ranges::find_if(grants.values(), [&](const auto &item) {
        return item.capability == capability;
      });
  return found == grants.values().end() ? nullptr : &*found;
}

PluginGrants *plugin_for(StoreState &state,
                         const permission::PluginId &plugin) {
  const auto found = std::ranges::find_if(
      state.plugins, [&](const auto &item) { return item.plugin == plugin; });
  return found == state.plugins.end() ? nullptr : &*found;
}

const PluginGrants *plugin_for(const StoreState &state,
                               const permission::PluginId &plugin) {
  const auto found = std::ranges::find_if(
      state.plugins, [&](const auto &item) { return item.plugin == plugin; });
  return found == state.plugins.end() ? nullptr : &*found;
}

void validate_bundle(const RequestBundle &bundle) {
  require(
      bundle.plugin_schema_version == kSecurePluginSchemaVersion,
      bundle.plugin_schema_version == 1
          ? "schema v1 is unsafe host code and cannot receive granular grants"
          : "only feature-gated schema v2 can receive granular grants");
  require(bundle.generation > 0, "grant binding generation must be nonzero");
  require(valid_digest(bundle.source_request_fingerprint.view()),
          "invalid source request fingerprint");
  permission::validate_requests(bundle.requests);
  const permission::Digest policy(
      permission::policy_request_fingerprint(bundle.requests));
  const permission::ActivationBinding binding{
      .plugin = bundle.plugin,
      .revision = bundle.revision,
      .policy_fingerprint = policy,
      .generation = bundle.generation,
  };
  permission::GrantSet empty;
  (void)permission::grant_fingerprint(binding.plugin, binding.revision,
                                      binding.policy_fingerprint, empty);
}

RevisionGrants revision_from(const RequestBundle &bundle) {
  validate_bundle(bundle);
  return {
      .binding = {.plugin = bundle.plugin,
                  .revision = bundle.revision,
                  .policy_fingerprint = permission::Digest(
                      permission::policy_request_fingerprint(bundle.requests)),
                  .generation = bundle.generation},
      .source_request_fingerprint = bundle.source_request_fingerprint,
      .requests = bundle.requests,
      .grants = {},
  };
}

void validate_revision(const RevisionGrants &revision,
                       const permission::PluginId &plugin) {
  require(revision.binding.plugin == plugin,
          "revision binding plugin does not match store key");
  require(valid_digest(revision.source_request_fingerprint.view()),
          "invalid persisted source request fingerprint");
  permission::validate_requests(revision.requests);
  require(revision.binding.policy_fingerprint ==
              permission::Digest(
                  permission::policy_request_fingerprint(revision.requests)),
          "persisted policy fingerprint mismatch");
  permission::PermissionAuthority authority(revision.binding, revision.requests,
                                            revision.grants);
  (void)authority;
}

void validate_state(const StoreState &state) {
  require(state.schema_version == kStoreSchemaVersion,
          "unsupported grant store schema");
  require(state.plugins.size() <= kMaximumPlugins,
          "grant store plugin limit exceeded");
  require(state.decisions.size() <= kMaximumDecisions,
          "grant store decision limit exceeded");
  require(state.next_decision_sequence > 0, "invalid next decision sequence");
  for (std::size_t index = 0; index < state.plugins.size(); ++index) {
    if (index > 0)
      require(state.plugins[index - 1].plugin < state.plugins[index].plugin,
              "persisted plugins are duplicate or not canonical-order");
    const auto &plugin = state.plugins[index];
    permission::GrantSet empty;
    (void)permission::grant_fingerprint(
        plugin.plugin, permission::Digest(std::string(64, '0')),
        permission::Digest(std::string(64, '0')), empty);
    if (plugin.active)
      validate_revision(*plugin.active, plugin.plugin);
    if (plugin.candidate)
      validate_revision(*plugin.candidate, plugin.plugin);
    require(plugin.epochs.size() <= 64,
            "persisted capability epoch count exceeds bound");
    for (std::size_t epoch_index = 0; epoch_index < plugin.epochs.size();
         ++epoch_index) {
      const auto &epoch = plugin.epochs[epoch_index];
      require(permission::find_capability(epoch.capability) != nullptr &&
                  epoch.epoch > 0,
              "invalid persisted capability epoch");
      if (epoch_index > 0)
        require(plugin.epochs[epoch_index - 1].capability < epoch.capability,
                "persisted capability epochs are duplicate or unordered");
    }
    const auto validate_epoch_floor = [&](const auto &revision) {
      if (!revision)
        return;
      for (const auto &grant : revision->grants.values()) {
        const auto found =
            std::ranges::find_if(plugin.epochs, [&](const auto &epoch) {
              return epoch.capability == grant.capability;
            });
        require(found != plugin.epochs.end() && found->epoch >= grant.epoch,
                "capability epoch floor is below a persisted grant");
      }
    };
    validate_epoch_floor(plugin.active);
    validate_epoch_floor(plugin.candidate);
  }
  std::uint64_t previous = 0;
  for (const auto &decision : state.decisions) {
    permission::validate_decision(decision);
    require(decision.sequence > previous,
            "decision sequences are not strictly monotonic");
    require(plugin_for(state, decision.plugin) != nullptr,
            "decision references an unknown plugin");
    previous = decision.sequence;
  }
  require(state.next_decision_sequence > previous,
          "next decision sequence does not advance history");
}

class Writer {
public:
  void bytes(std::span<const std::byte> value) {
    require(data_.size() + value.size() <= kMaximumStoreBytes,
            "serialized grant store exceeds byte limit");
    data_.insert(data_.end(), value.begin(), value.end());
  }
  void u8(std::uint8_t value) {
    data_.push_back(static_cast<std::byte>(value));
  }
  void u16(std::uint16_t value) {
    u8(static_cast<std::uint8_t>(value >> 8));
    u8(static_cast<std::uint8_t>(value));
  }
  void u32(std::uint32_t value) {
    for (int shift = 24; shift >= 0; shift -= 8)
      u8(static_cast<std::uint8_t>(value >> shift));
  }
  void u64(std::uint64_t value) {
    for (int shift = 56; shift >= 0; shift -= 8)
      u8(static_cast<std::uint8_t>(value >> shift));
  }
  void text(std::string_view value) {
    require(value.size() <= std::numeric_limits<std::uint16_t>::max(),
            "persisted text exceeds length bound");
    u16(static_cast<std::uint16_t>(value.size()));
    bytes(std::as_bytes(std::span(value.data(), value.size())));
  }
  [[nodiscard]] const std::vector<std::byte> &data() const { return data_; }

private:
  std::vector<std::byte> data_;
};

class Reader {
public:
  explicit Reader(std::span<const std::byte> data) : data_(data) {}
  std::uint8_t u8() {
    require(position_ < data_.size(), "truncated grant store");
    return std::to_integer<std::uint8_t>(data_[position_++]);
  }
  std::uint16_t u16() {
    return static_cast<std::uint16_t>((static_cast<std::uint16_t>(u8()) << 8) |
                                      u8());
  }
  std::uint32_t u32() {
    std::uint32_t value = 0;
    for (int index = 0; index < 4; ++index)
      value = (value << 8) | u8();
    return value;
  }
  std::uint64_t u64() {
    std::uint64_t value = 0;
    for (int index = 0; index < 8; ++index)
      value = (value << 8) | u8();
    return value;
  }
  std::string text() {
    const auto size = u16();
    require(size <= data_.size() - position_, "truncated persisted text");
    std::string value(reinterpret_cast<const char *>(data_.data() + position_),
                      size);
    position_ += size;
    require(value.find('\0') == std::string::npos,
            "persisted text contains NUL");
    return value;
  }
  std::span<const std::byte> take(std::size_t size) {
    require(size <= data_.size() - position_, "truncated persisted bytes");
    const auto result = data_.subspan(position_, size);
    position_ += size;
    return result;
  }
  [[nodiscard]] bool complete() const { return position_ == data_.size(); }

private:
  std::span<const std::byte> data_;
  std::size_t position_ = 0;
};

void write_scope(Writer &writer, const permission::Scope &scope) {
  writer.u8(static_cast<std::uint8_t>(scope.index()));
  if (const auto *quota = std::get_if<permission::QuotaScope>(&scope)) {
    writer.u64(quota->total_bytes);
    writer.u64(quota->item_bytes);
  } else if (const auto *tokens = std::get_if<permission::TokenScope>(&scope)) {
    writer.u8(static_cast<std::uint8_t>(tokens->tokens.size()));
    for (const auto &token : tokens->tokens.values())
      writer.text(token.view());
  } else if (const auto *resources =
                 std::get_if<permission::ResourceScope>(&scope)) {
    writer.u8(static_cast<std::uint8_t>(resources->resources.size()));
    for (const auto value : resources->resources.values())
      writer.u32(value);
    writer.u8(static_cast<std::uint8_t>(resources->operations.size()));
    for (const auto operation : resources->operations.values())
      writer.u16(static_cast<std::uint16_t>(operation));
  } else if (const auto *http = std::get_if<permission::HttpScope>(&scope)) {
    writer.u8(static_cast<std::uint8_t>(http->schemes.size()));
    for (const auto &value : http->schemes.values())
      writer.text(value.view());
    writer.u8(static_cast<std::uint8_t>(http->hosts.size()));
    for (const auto &value : http->hosts.values())
      writer.text(value.view());
    writer.u8(static_cast<std::uint8_t>(http->methods.size()));
    for (const auto &value : http->methods.values())
      writer.text(value.view());
    writer.u8(static_cast<std::uint8_t>(http->ports.size()));
    for (const auto value : http->ports.values())
      writer.u16(value);
    writer.u8(http->allow_redirects ? 1 : 0);
    writer.u8(http->allow_loopback ? 1 : 0);
    writer.u8(http->allow_unix_socket ? 1 : 0);
  }
}

permission::Scope read_scope(Reader &reader) {
  const auto kind = reader.u8();
  if (kind == static_cast<std::uint8_t>(permission::ScopeKind::none))
    return permission::NoScope{};
  if (kind == static_cast<std::uint8_t>(permission::ScopeKind::quota))
    return permission::QuotaScope{.total_bytes = reader.u64(),
                                  .item_bytes = reader.u64()};
  if (kind == static_cast<std::uint8_t>(permission::ScopeKind::tokens)) {
    permission::TokenScope scope;
    const auto count = reader.u8();
    require(count <= 16, "persisted token scope exceeds bound");
    for (std::uint8_t index = 0; index < count; ++index)
      require(scope.tokens.insert(permission::ScopeToken(reader.text())),
              "duplicate persisted scope token");
    return scope;
  }
  if (kind == static_cast<std::uint8_t>(permission::ScopeKind::resources)) {
    permission::ResourceScope scope;
    const auto resource_count = reader.u8();
    require(resource_count <= 32, "persisted resource scope exceeds bound");
    for (std::uint8_t index = 0; index < resource_count; ++index)
      require(scope.resources.insert(reader.u32()),
              "duplicate persisted resource id");
    const auto operation_count = reader.u8();
    require(operation_count <= 16, "persisted operation scope exceeds bound");
    for (std::uint8_t index = 0; index < operation_count; ++index)
      require(scope.operations.insert(
                  static_cast<permission::OperationId>(reader.u16())),
              "duplicate persisted operation id");
    return scope;
  }
  if (kind == static_cast<std::uint8_t>(permission::ScopeKind::http)) {
    permission::HttpScope scope;
    const auto read_tokens = [&](auto &target, std::uint8_t maximum) {
      const auto count = reader.u8();
      require(count <= maximum, "persisted HTTP token scope exceeds bound");
      for (std::uint8_t index = 0; index < count; ++index)
        require(target.insert(permission::ScopeToken(reader.text())),
                "duplicate persisted HTTP scope token");
    };
    read_tokens(scope.schemes, 4);
    read_tokens(scope.hosts, 16);
    read_tokens(scope.methods, 8);
    const auto port_count = reader.u8();
    require(port_count <= 16, "persisted HTTP port scope exceeds bound");
    for (std::uint8_t index = 0; index < port_count; ++index)
      require(scope.ports.insert(reader.u16()),
              "duplicate persisted HTTP port");
    const auto redirects = reader.u8();
    const auto loopback = reader.u8();
    const auto unix_socket = reader.u8();
    require(redirects <= 1 && loopback <= 1 && unix_socket <= 1,
            "invalid persisted HTTP scope flag");
    scope.allow_redirects = redirects == 1;
    scope.allow_loopback = loopback == 1;
    scope.allow_unix_socket = unix_socket == 1;
    return scope;
  }
  fail("unknown persisted scope kind");
}

void write_key(Writer &writer, const permission::CapabilityKey &key) {
  writer.text(key.id.view());
  writer.u16(key.version);
}

permission::CapabilityKey read_key(Reader &reader) {
  return {.id = permission::CapabilityId(reader.text()),
          .version = reader.u16()};
}

void write_requests(Writer &writer, const permission::RequestSet &requests) {
  writer.u16(static_cast<std::uint16_t>(requests.size()));
  for (const auto &request : requests.values()) {
    write_key(writer, request.capability);
    writer.u8(request.required ? 1 : 0);
    write_scope(writer, request.scope);
  }
}

permission::RequestSet read_requests(Reader &reader) {
  permission::RequestSet requests;
  const auto count = reader.u16();
  require(count <= 64, "persisted request count exceeds bound");
  for (std::uint16_t index = 0; index < count; ++index) {
    permission::CapabilityRequest request;
    request.capability = read_key(reader);
    const auto required = reader.u8();
    require(required <= 1, "invalid persisted required flag");
    request.required = required == 1;
    request.scope = read_scope(reader);
    requests.push_back(std::move(request));
  }
  return requests;
}

void write_grants(Writer &writer, const permission::GrantSet &grants) {
  writer.u16(static_cast<std::uint16_t>(grants.size()));
  for (const auto &grant : grants.values()) {
    write_key(writer, grant.capability);
    writer.u8(static_cast<std::uint8_t>(grant.state));
    writer.u64(grant.epoch);
    write_scope(writer, grant.scope);
  }
}

permission::GrantSet read_grants(Reader &reader) {
  permission::GrantSet grants;
  const auto count = reader.u16();
  require(count <= 64, "persisted grant count exceeds bound");
  for (std::uint16_t index = 0; index < count; ++index) {
    permission::GrantRecord grant;
    grant.capability = read_key(reader);
    grant.state = static_cast<permission::GrantState>(reader.u8());
    grant.epoch = reader.u64();
    grant.scope = read_scope(reader);
    grants.push_back(std::move(grant));
  }
  return grants;
}

void write_revision(Writer &writer, const RevisionGrants &revision) {
  writer.text(revision.binding.revision.view());
  writer.text(revision.source_request_fingerprint.view());
  writer.text(revision.binding.policy_fingerprint.view());
  writer.u64(revision.binding.generation);
  write_requests(writer, revision.requests);
  write_grants(writer, revision.grants);
}

RevisionGrants read_revision(Reader &reader,
                             const permission::PluginId &plugin) {
  RevisionGrants revision;
  revision.binding.plugin = plugin;
  revision.binding.revision = permission::Digest(reader.text());
  revision.source_request_fingerprint = permission::Digest(reader.text());
  revision.binding.policy_fingerprint = permission::Digest(reader.text());
  revision.binding.generation = reader.u64();
  revision.requests = read_requests(reader);
  revision.grants = read_grants(reader);
  return revision;
}

void write_decision(Writer &writer,
                    const permission::UserDecisionRecord &decision) {
  writer.u64(decision.sequence);
  writer.text(decision.plugin.view());
  writer.text(decision.revision.view());
  writer.text(decision.source_request_fingerprint.view());
  writer.text(decision.policy_request_fingerprint.view());
  write_key(writer, decision.capability);
  write_scope(writer, decision.requested_scope);
  write_scope(writer, decision.decided_scope);
  writer.u8(static_cast<std::uint8_t>(decision.decision));
  writer.u8(static_cast<std::uint8_t>(decision.actor));
  writer.u64(decision.decided_wall_seconds);
}

permission::UserDecisionRecord read_decision(Reader &reader) {
  permission::UserDecisionRecord decision;
  decision.sequence = reader.u64();
  decision.plugin = permission::PluginId(reader.text());
  decision.revision = permission::Digest(reader.text());
  decision.source_request_fingerprint = permission::Digest(reader.text());
  decision.policy_request_fingerprint = permission::Digest(reader.text());
  decision.capability = read_key(reader);
  decision.requested_scope = read_scope(reader);
  decision.decided_scope = read_scope(reader);
  decision.decision = static_cast<permission::UserDecision>(reader.u8());
  decision.actor = static_cast<permission::DecisionActor>(reader.u8());
  decision.decided_wall_seconds = reader.u64();
  return decision;
}

std::vector<std::byte> serialize(const StoreState &state) {
  validate_state(state);
  Writer writer;
  writer.bytes(kMagic);
  writer.u16(state.schema_version);
  writer.u64(state.mutation_sequence);
  writer.u64(state.next_decision_sequence);
  writer.u16(static_cast<std::uint16_t>(state.plugins.size()));
  for (const auto &plugin : state.plugins) {
    writer.text(plugin.plugin.view());
    writer.u8(plugin.active.has_value() ? 1 : 0);
    if (plugin.active)
      write_revision(writer, *plugin.active);
    writer.u8(plugin.candidate.has_value() ? 1 : 0);
    if (plugin.candidate)
      write_revision(writer, *plugin.candidate);
    writer.u16(static_cast<std::uint16_t>(plugin.epochs.size()));
    for (const auto &epoch : plugin.epochs) {
      write_key(writer, epoch.capability);
      writer.u64(epoch.epoch);
    }
  }
  writer.u32(static_cast<std::uint32_t>(state.decisions.size()));
  for (const auto &decision : state.decisions)
    write_decision(writer, decision);
  return writer.data();
}

StoreState deserialize(std::span<const std::byte> bytes) {
  require(bytes.size() <= kMaximumStoreBytes, "grant store exceeds byte limit");
  Reader reader(bytes);
  require(std::ranges::equal(reader.take(kMagic.size()), kMagic),
          "invalid grant store magic");
  StoreState state;
  state.schema_version = reader.u16();
  state.mutation_sequence = reader.u64();
  state.next_decision_sequence = reader.u64();
  const auto plugin_count = reader.u16();
  require(plugin_count <= kMaximumPlugins,
          "persisted plugin count exceeds bound");
  state.plugins.reserve(plugin_count);
  for (std::uint16_t index = 0; index < plugin_count; ++index) {
    PluginGrants plugin;
    plugin.plugin = permission::PluginId(reader.text());
    const auto active = reader.u8();
    require(active <= 1, "invalid persisted active flag");
    if (active == 1)
      plugin.active = read_revision(reader, plugin.plugin);
    const auto candidate = reader.u8();
    require(candidate <= 1, "invalid persisted candidate flag");
    if (candidate == 1)
      plugin.candidate = read_revision(reader, plugin.plugin);
    const auto epoch_count = reader.u16();
    require(epoch_count <= 64,
            "persisted capability epoch count exceeds bound");
    plugin.epochs.reserve(epoch_count);
    for (std::uint16_t epoch_index = 0; epoch_index < epoch_count;
         ++epoch_index)
      plugin.epochs.push_back(
          {.capability = read_key(reader), .epoch = reader.u64()});
    state.plugins.push_back(std::move(plugin));
  }
  const auto decision_count = reader.u32();
  require(decision_count <= kMaximumDecisions,
          "persisted decision count exceeds bound");
  state.decisions.reserve(decision_count);
  for (std::uint32_t index = 0; index < decision_count; ++index)
    state.decisions.push_back(read_decision(reader));
  require(reader.complete(), "grant store has trailing data");
  validate_state(state);
  return state;
}

void validate_owner_file(const struct stat &metadata, mode_t expected_type,
                         std::string_view label) {
  require((metadata.st_mode & S_IFMT) == expected_type,
          std::string(label) + " has wrong file type");
  require(metadata.st_uid == geteuid(),
          std::string(label) + " is not owned by current user");
  require((metadata.st_mode & 0077) == 0,
          std::string(label) + " permits group or other access");
}

FileDescriptor open_directory(const std::filesystem::path &path, bool create) {
  require(!path.empty(), "grant store directory is empty");
  for (const auto &component : path)
    require(component != "..",
            "grant store path must not contain parent traversal");
  const auto normalized = path.lexically_normal();
  FileDescriptor current(open(normalized.is_absolute() ? "/" : ".",
                              O_RDONLY | O_DIRECTORY | O_CLOEXEC));
  if (!current)
    fail(system_error("cannot open grant store path base"));
  std::vector<std::string> components;
  for (const auto &component : normalized) {
    const auto value = component.string();
    if (value.empty() || value == "/" || value == ".")
      continue;
    require(value != "..",
            "grant store path must not contain parent traversal");
    components.push_back(value);
  }
  require(!components.empty(), "grant store cannot use filesystem root");
  for (std::size_t index = 0; index < components.size(); ++index) {
    const bool final = index + 1 == components.size();
    int next = openat(current.get(), components[index].c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (next < 0 && errno == ENOENT && create) {
      if (mkdirat(current.get(), components[index].c_str(), 0700) != 0 &&
          errno != EEXIST)
        fail(system_error("cannot create grant store directory"));
      next = openat(current.get(), components[index].c_str(),
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    }
    if (next < 0) {
      if (errno == ENOENT && !create)
        return FileDescriptor();
      fail(system_error("cannot open grant store directory component"));
    }
    current = FileDescriptor(next);
    if (final) {
      struct stat metadata{};
      if (fstat(current.get(), &metadata) != 0)
        fail(system_error("cannot inspect grant store directory"));
      validate_owner_file(metadata, S_IFDIR, "grant store directory");
    }
  }
  return current;
}

std::optional<std::vector<std::byte>> read_file(int directory) {
  FileDescriptor file(
      openat(directory, kStoreFile.data(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
  if (!file) {
    if (errno == ENOENT)
      return std::nullopt;
    fail(system_error("cannot open grant store file"));
  }
  struct stat metadata{};
  if (fstat(file.get(), &metadata) != 0)
    fail(system_error("cannot inspect grant store file"));
  validate_owner_file(metadata, S_IFREG, "grant store file");
  require(metadata.st_size >= 0 && static_cast<std::uint64_t>(
                                       metadata.st_size) <= kMaximumStoreBytes,
          "grant store file exceeds byte limit");
  std::vector<std::byte> data(static_cast<std::size_t>(metadata.st_size));
  std::size_t position = 0;
  while (position < data.size()) {
    const auto result =
        ::read(file.get(), data.data() + position, data.size() - position);
    if (result < 0 && errno == EINTR)
      continue;
    if (result <= 0)
      fail("grant store file truncated while reading");
    position += static_cast<std::size_t>(result);
  }
  return data;
}

StoreState load(int directory) {
  const auto data = read_file(directory);
  return data ? deserialize(*data) : StoreState{};
}

FileDescriptor lock_directory(int directory) {
  FileDescriptor lock(openat(directory, kLockFile.data(),
                             O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (!lock)
    fail(system_error("cannot open grant store lock"));
  struct stat metadata{};
  if (fstat(lock.get(), &metadata) != 0)
    fail(system_error("cannot inspect grant store lock"));
  validate_owner_file(metadata, S_IFREG, "grant store lock");
  if (flock(lock.get(), LOCK_EX) != 0)
    fail(system_error("cannot lock grant store"));
  return lock;
}

void write_all(int descriptor, std::span<const std::byte> data) {
  std::size_t position = 0;
  while (position < data.size()) {
    const auto result =
        ::write(descriptor, data.data() + position, data.size() - position);
    if (result < 0 && errno == EINTR)
      continue;
    if (result <= 0)
      fail(system_error("cannot write grant store"));
    position += static_cast<std::size_t>(result);
  }
}

void persist(int directory, const StoreState &state) {
  const auto data = serialize(state);
  const std::string temporary =
      ".grants-v1.tmp." + std::to_string(static_cast<long long>(getpid())) +
      "." + std::to_string(state.mutation_sequence);
  FileDescriptor file(
      openat(directory, temporary.c_str(),
             O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (!file)
    fail(system_error("cannot create atomic grant store file"));
  bool renamed = false;
  try {
    write_all(file.get(), data);
    if (fsync(file.get()) != 0)
      fail(system_error("cannot sync atomic grant store file"));
    struct stat metadata{};
    if (fstat(file.get(), &metadata) != 0)
      fail(system_error("cannot inspect atomic grant store file"));
    validate_owner_file(metadata, S_IFREG, "atomic grant store file");
    if (renameat(directory, temporary.c_str(), directory, kStoreFile.data()) !=
        0)
      fail(system_error("cannot atomically replace grant store"));
    renamed = true;
    if (fsync(directory) != 0)
      fail(system_error("cannot sync grant store directory"));
  } catch (...) {
    if (!renamed)
      (void)unlinkat(directory, temporary.c_str(), 0);
    throw;
  }
}

template <typename Mutation>
auto update_store(const std::filesystem::path &path, Mutation mutation) {
  auto directory = open_directory(path, true);
  auto lock = lock_directory(directory.get());
  auto state = load(directory.get());
  auto result = mutation(state);
  validate_state(state);
  persist(directory.get(), state);
  return result;
}

permission::DeltaSet delta_from(const PluginGrants *plugin,
                                const RequestBundle &bundle) {
  if (plugin == nullptr || !plugin->active) {
    permission::RequestSet empty_requests;
    permission::GrantSet empty_grants;
    return permission::compute_update_delta(empty_requests, empty_grants,
                                            bundle.requests);
  }
  return permission::compute_update_delta(
      plugin->active->requests, plugin->active->grants, bundle.requests);
}

Preview preview_in(const StoreState &state, const RequestBundle &bundle,
                   const permission::CapabilityKey &capability) {
  validate_bundle(bundle);
  const auto prospective = revision_from(bundle);
  const auto *request = request_for(bundle.requests, capability);
  require(request != nullptr, "capability is not declared by request bundle");
  const auto *plugin = plugin_for(state, bundle.plugin);
  Preview result{.expected_mutation_sequence = state.mutation_sequence,
                 .target = TargetRevision::candidate,
                 .request_delta = delta_from(plugin, bundle),
                 .current_grant = std::nullopt,
                 .binding = prospective.binding,
                 .source_request_fingerprint =
                     prospective.source_request_fingerprint};
  if (plugin == nullptr)
    return result;
  reject_source_alias(plugin->active, prospective);
  reject_source_alias(plugin->candidate, prospective);
  const RevisionGrants *target = nullptr;
  if (plugin->active && same_revision(*plugin->active, prospective)) {
    result.target = TargetRevision::active;
    target = &*plugin->active;
  } else if (plugin->candidate &&
             same_revision(*plugin->candidate, prospective)) {
    target = &*plugin->candidate;
  } else if (plugin->candidate) {
    fail("a different candidate revision is already awaiting a lifecycle "
         "decision");
  }
  if (target != nullptr) {
    const auto *current = grant_for(target->grants, capability);
    if (current != nullptr)
      result.current_grant = *current;
  }
  return result;
}

RevisionGrants &ensure_target(PluginGrants &plugin, const RequestBundle &bundle,
                              const permission::DeltaSet &delta,
                              TargetRevision &target_kind) {
  const auto prospective = revision_from(bundle);
  reject_source_alias(plugin.active, prospective);
  reject_source_alias(plugin.candidate, prospective);
  if (plugin.active && same_revision(*plugin.active, prospective)) {
    target_kind = TargetRevision::active;
    return *plugin.active;
  }
  target_kind = TargetRevision::candidate;
  if (plugin.candidate) {
    require(same_revision(*plugin.candidate, prospective),
            "different candidate revision already exists");
    return *plugin.candidate;
  }
  RevisionGrants candidate = prospective;
  for (const auto &entry : delta.values()) {
    if (entry.inherited_grant)
      candidate.grants.push_back(*entry.inherited_grant);
  }
  plugin.candidate = std::move(candidate);
  return *plugin.candidate;
}

CapabilityEpoch *epoch_for(PluginGrants &plugin,
                           const permission::CapabilityKey &capability) {
  const auto found = std::ranges::find_if(plugin.epochs, [&](const auto &item) {
    return item.capability == capability;
  });
  return found == plugin.epochs.end() ? nullptr : &*found;
}

std::uint64_t next_epoch(PluginGrants &plugin,
                         const permission::CapabilityKey &capability) {
  auto *epoch = epoch_for(plugin, capability);
  if (epoch == nullptr) {
    require(plugin.epochs.size() < 64, "capability epoch limit reached");
    plugin.epochs.push_back({.capability = capability, .epoch = 1});
    std::ranges::sort(plugin.epochs, [](const auto &left, const auto &right) {
      return left.capability < right.capability;
    });
    return 1;
  }
  require(epoch->epoch < std::numeric_limits<std::uint64_t>::max(),
          "grant epoch exhausted");
  return ++epoch->epoch;
}

std::string escape_json(std::string_view value) {
  std::string result;
  result.reserve(value.size() + 2);
  for (const unsigned char byte : value) {
    switch (byte) {
    case '"':
      result += "\\\"";
      break;
    case '\\':
      result += "\\\\";
      break;
    case '\b':
      result += "\\b";
      break;
    case '\f':
      result += "\\f";
      break;
    case '\n':
      result += "\\n";
      break;
    case '\r':
      result += "\\r";
      break;
    case '\t':
      result += "\\t";
      break;
    default:
      if (byte < 0x20) {
        constexpr char hex[] = "0123456789abcdef";
        result += "\\u00";
        result.push_back(hex[byte >> 4]);
        result.push_back(hex[byte & 0x0f]);
      } else {
        result.push_back(static_cast<char>(byte));
      }
    }
  }
  return result;
}

std::string json_quote(std::string_view value) {
  return "\"" + escape_json(value) + "\"";
}

std::string key_json(const permission::CapabilityKey &key) {
  return "{\"id\":" + json_quote(key.id.view()) +
         ",\"version\":" + std::to_string(key.version) + "}";
}

std::string scope_json(const permission::Scope &scope) {
  if (std::holds_alternative<permission::NoScope>(scope))
    return "{\"kind\":\"none\"}";
  if (const auto *quota = std::get_if<permission::QuotaScope>(&scope))
    return "{\"kind\":\"quota\",\"totalBytes\":" +
           std::to_string(quota->total_bytes) +
           ",\"itemBytes\":" + std::to_string(quota->item_bytes) + "}";
  if (const auto *tokens = std::get_if<permission::TokenScope>(&scope)) {
    std::string result = "{\"kind\":\"tokens\",\"values\":[";
    bool first = true;
    for (const auto &token : tokens->tokens.values()) {
      if (!first)
        result += ',';
      first = false;
      result += json_quote(token.view());
    }
    return result + "]}";
  }
  if (const auto *resources = std::get_if<permission::ResourceScope>(&scope)) {
    std::string result = "{\"kind\":\"resources\",\"resourceIds\":[";
    bool first = true;
    for (const auto value : resources->resources.values()) {
      if (!first)
        result += ',';
      first = false;
      result += std::to_string(value);
    }
    result += "],\"operations\":[";
    first = true;
    for (const auto operation : resources->operations.values()) {
      if (!first)
        result += ',';
      first = false;
      result += std::to_string(static_cast<std::uint16_t>(operation));
    }
    return result + "]}";
  }
  return "{\"kind\":\"http\",\"registered\":false}";
}

std::string grant_state(permission::GrantState state) {
  switch (state) {
  case permission::GrantState::granted:
    return "granted";
  case permission::GrantState::denied:
    return "denied";
  case permission::GrantState::revoked:
    return "revoked";
  }
  fail("invalid grant state");
}

std::string target_name(TargetRevision target) {
  return target == TargetRevision::active ? "active" : "candidate";
}

std::string delta_name(permission::DeltaKind kind) {
  switch (kind) {
  case permission::DeltaKind::unchanged:
    return "unchanged";
  case permission::DeltaKind::narrowed:
    return "narrowed";
  case permission::DeltaKind::expanded:
    return "expanded";
  case permission::DeltaKind::incomparable:
    return "incomparable";
  case permission::DeltaKind::added:
    return "added";
  case permission::DeltaKind::removed:
    return "removed";
  case permission::DeltaKind::requirement_changed:
    return "requirement-changed";
  }
  fail("invalid delta kind");
}

std::string grant_json(const permission::GrantRecord &grant) {
  return "{\"capability\":" + key_json(grant.capability) +
         ",\"scope\":" + scope_json(grant.scope) +
         ",\"state\":" + json_quote(grant_state(grant.state)) +
         ",\"epoch\":" + std::to_string(grant.epoch) + "}";
}

std::string revision_json(const RevisionGrants &revision) {
  std::vector<const permission::GrantRecord *> sorted;
  for (const auto &grant : revision.grants.values())
    sorted.push_back(&grant);
  std::ranges::sort(sorted, [](auto left, auto right) {
    return left->capability < right->capability;
  });
  std::string grants = "[";
  for (std::size_t index = 0; index < sorted.size(); ++index) {
    if (index > 0)
      grants += ',';
    grants += grant_json(*sorted[index]);
  }
  grants += ']';
  return "{\"revision\":" + json_quote(revision.binding.revision.view()) +
         ",\"sourceRequestFingerprint\":" +
         json_quote(revision.source_request_fingerprint.view()) +
         ",\"policyFingerprint\":" +
         json_quote(revision.binding.policy_fingerprint.view()) +
         ",\"generation\":" + std::to_string(revision.binding.generation) +
         ",\"grantFingerprint\":" +
         json_quote(permission::grant_fingerprint(
             revision.binding.plugin, revision.binding.revision,
             revision.binding.policy_fingerprint, revision.grants)) +
         ",\"grants\":" + grants + "}";
}

} // namespace

GrantStore::GrantStore(std::filesystem::path directory)
    : directory_(std::move(directory)) {
  require(!directory_.empty(), "grant store directory is required");
}

StoreState GrantStore::read() const {
  auto directory = open_directory(directory_, false);
  return directory ? load(directory.get()) : StoreState{};
}

Preview GrantStore::preview(const RequestBundle &bundle,
                            const permission::CapabilityKey &capability) const {
  return preview_in(read(), bundle, capability);
}

MutationResult GrantStore::decide(
    const RequestBundle &bundle, const permission::CapabilityKey &capability,
    const std::optional<permission::Scope> &granted_scope,
    permission::UserDecision decision, permission::DecisionActor actor,
    std::uint64_t decided_wall_seconds,
    std::uint64_t expected_mutation_sequence) {
  validate_bundle(bundle);
  require(decision == permission::UserDecision::deny ||
              actor == permission::DecisionActor::interactive_cli ||
              actor == permission::DecisionActor::trusted_ui,
          "unattended or reviewed-policy actors cannot grant authority");
  require(decision == permission::UserDecision::grant || !granted_scope,
          "denial does not accept an alternate scope");
  return update_store(directory_, [&](StoreState &state) {
    require(state.mutation_sequence == expected_mutation_sequence,
            "grant store changed after permission preview; review again");
    require(state.mutation_sequence < std::numeric_limits<std::uint64_t>::max(),
            "grant store mutation sequence exhausted");
    require(state.next_decision_sequence <
                std::numeric_limits<std::uint64_t>::max(),
            "decision sequence exhausted");
    require(state.decisions.size() < kMaximumDecisions,
            "decision history limit reached");
    const auto before = preview_in(state, bundle, capability);
    auto *plugin = plugin_for(state, bundle.plugin);
    if (plugin == nullptr) {
      require(state.plugins.size() < kMaximumPlugins,
              "grant store plugin limit reached");
      state.plugins.push_back({.plugin = bundle.plugin,
                               .active = std::nullopt,
                               .candidate = std::nullopt,
                               .epochs = {}});
      std::ranges::sort(state.plugins, [](const auto &left, const auto &right) {
        return left.plugin < right.plugin;
      });
      plugin = plugin_for(state, bundle.plugin);
    }
    TargetRevision target_kind = TargetRevision::candidate;
    auto &target =
        ensure_target(*plugin, bundle, before.request_delta, target_kind);
    const auto *request = request_for(target.requests, capability);
    require(request != nullptr,
            "capability is not declared by target revision");
    const permission::Scope decided_scope =
        decision == permission::UserDecision::grant
            ? granted_scope.value_or(request->scope)
            : request->scope;
    permission::UserDecisionRecord record{
        .sequence = state.next_decision_sequence,
        .plugin = bundle.plugin,
        .revision = target.binding.revision,
        .source_request_fingerprint = target.source_request_fingerprint,
        .policy_request_fingerprint = target.binding.policy_fingerprint,
        .capability = capability,
        .requested_scope = request->scope,
        .decided_scope = decided_scope,
        .decision = decision,
        .actor = actor,
        .decided_wall_seconds = decided_wall_seconds,
    };
    permission::validate_decision(record);
    const auto epoch = next_epoch(*plugin, capability);
    permission::GrantRecord grant{
        .capability = capability,
        .scope = decided_scope,
        .state = decision == permission::UserDecision::grant
                     ? permission::GrantState::granted
                     : permission::GrantState::denied,
        .epoch = epoch,
    };
    if (auto *existing = grant_for(target.grants, capability))
      *existing = grant;
    else
      target.grants.push_back(grant);
    state.decisions.push_back(record);
    ++state.next_decision_sequence;
    ++state.mutation_sequence;
    return MutationResult{
        .mutation_sequence = state.mutation_sequence,
        .decision_sequence = record.sequence,
        .target = target_kind,
        .grant = grant,
        .grant_fingerprint = permission::grant_fingerprint(
            target.binding.plugin, target.binding.revision,
            target.binding.policy_fingerprint, target.grants),
    };
  });
}

RevocationResult
GrantStore::revoke(const RequestBundle &bundle,
                   const permission::CapabilityKey &capability) {
  validate_bundle(bundle);
  return update_store(directory_, [&](StoreState &state) {
    require(state.mutation_sequence < std::numeric_limits<std::uint64_t>::max(),
            "grant store mutation sequence exhausted");
    auto *plugin = plugin_for(state, bundle.plugin);
    require(plugin != nullptr, "plugin has no persisted grants");
    const auto prospective = revision_from(bundle);
    reject_source_alias(plugin->active, prospective);
    reject_source_alias(plugin->candidate, prospective);
    RevisionGrants *target = nullptr;
    TargetRevision target_kind = TargetRevision::candidate;
    if (plugin->active && same_revision(*plugin->active, prospective)) {
      target = &*plugin->active;
      target_kind = TargetRevision::active;
    } else if (plugin->candidate &&
               same_revision(*plugin->candidate, prospective)) {
      target = &*plugin->candidate;
    }
    require(target != nullptr,
            "revocation binding does not match active or candidate revision");
    require(grant_for(target->grants, capability) != nullptr,
            "cannot revoke a capability without a grant record");
    permission::PermissionAuthority authority(target->binding, target->requests,
                                              target->grants);
    (void)authority.revoke(capability);
    target->grants = authority.grants();
    auto *grant = grant_for(target->grants, capability);
    require(grant != nullptr && grant->state == permission::GrantState::revoked,
            "revocation did not persist revoked state");
    grant->epoch = next_epoch(*plugin, capability);
    const auto *definition = permission::find_capability(capability);
    require(definition != nullptr, "unknown capability during revocation");
    ++state.mutation_sequence;
    return RevocationResult{
        .mutation_sequence = state.mutation_sequence,
        .target = target_kind,
        .grant = *grant,
        .action = definition->revocation,
        .grant_fingerprint = permission::grant_fingerprint(
            target->binding.plugin, target->binding.revision,
            target->binding.policy_fingerprint, target->grants),
    };
  });
}

void GrantStore::activate_candidate(
    const permission::ActivationBinding &binding) {
  update_store(directory_, [&](StoreState &state) {
    require(state.mutation_sequence < std::numeric_limits<std::uint64_t>::max(),
            "grant store mutation sequence exhausted");
    auto *plugin = plugin_for(state, binding.plugin);
    require(plugin != nullptr && plugin->candidate.has_value(),
            "candidate grant revision does not exist");
    require(same_binding(plugin->candidate->binding, binding),
            "candidate activation binding mismatch");
    for (const auto &request : plugin->candidate->requests.values()) {
      if (!request.required)
        continue;
      const auto *grant =
          grant_for(plugin->candidate->grants, request.capability);
      require(grant != nullptr &&
                  grant->state == permission::GrantState::granted,
              "required capability is not granted");
    }
    plugin->active = std::move(plugin->candidate);
    plugin->candidate.reset();
    ++state.mutation_sequence;
    return 0;
  });
}

void GrantStore::discard_candidate(const permission::PluginId &plugin_id) {
  update_store(directory_, [&](StoreState &state) {
    require(state.mutation_sequence < std::numeric_limits<std::uint64_t>::max(),
            "grant store mutation sequence exhausted");
    auto *plugin = plugin_for(state, plugin_id);
    require(plugin != nullptr && plugin->candidate.has_value(),
            "candidate grant revision does not exist");
    plugin->candidate.reset();
    ++state.mutation_sequence;
    return 0;
  });
}

RequestBundle make_bundle(std::uint16_t plugin_schema_version,
                          permission::PluginId plugin,
                          permission::Digest revision,
                          permission::Digest source_request_fingerprint,
                          std::uint64_t generation,
                          permission::RequestSet requests) {
  RequestBundle bundle{
      .plugin_schema_version = plugin_schema_version,
      .plugin = std::move(plugin),
      .revision = std::move(revision),
      .source_request_fingerprint = std::move(source_request_fingerprint),
      .generation = generation,
      .requests = std::move(requests),
  };
  validate_bundle(bundle);
  return bundle;
}

std::string state_json(const StoreState &state) {
  validate_state(state);
  std::string plugins = "[";
  for (std::size_t index = 0; index < state.plugins.size(); ++index) {
    if (index > 0)
      plugins += ',';
    const auto &plugin = state.plugins[index];
    std::string epochs = "[";
    for (std::size_t epoch_index = 0; epoch_index < plugin.epochs.size();
         ++epoch_index) {
      if (epoch_index > 0)
        epochs += ',';
      epochs +=
          "{\"capability\":" + key_json(plugin.epochs[epoch_index].capability) +
          ",\"epoch\":" + std::to_string(plugin.epochs[epoch_index].epoch) +
          "}";
    }
    epochs += ']';
    plugins += "{\"plugin\":" + json_quote(plugin.plugin.view()) +
               ",\"active\":" +
               (plugin.active ? revision_json(*plugin.active) : "null") +
               ",\"candidate\":" +
               (plugin.candidate ? revision_json(*plugin.candidate) : "null") +
               ",\"epochs\":" + epochs + "}";
  }
  plugins += ']';
  std::string decisions = "[";
  for (std::size_t index = 0; index < state.decisions.size(); ++index) {
    if (index > 0)
      decisions += ',';
    const auto &decision = state.decisions[index];
    decisions +=
        "{\"sequence\":" + std::to_string(decision.sequence) +
        ",\"plugin\":" + json_quote(decision.plugin.view()) +
        ",\"revision\":" + json_quote(decision.revision.view()) +
        ",\"sourceRequestFingerprint\":" +
        json_quote(decision.source_request_fingerprint.view()) +
        ",\"policyFingerprint\":" +
        json_quote(decision.policy_request_fingerprint.view()) +
        ",\"capability\":" + key_json(decision.capability) +
        ",\"requestedScope\":" + scope_json(decision.requested_scope) +
        ",\"decidedScope\":" + scope_json(decision.decided_scope) +
        ",\"decision\":" +
        json_quote(decision.decision == permission::UserDecision::grant
                       ? "grant"
                       : "deny") +
        ",\"actor\":" +
        json_quote(decision.actor == permission::DecisionActor::interactive_cli
                       ? "interactive-cli"
                   : decision.actor == permission::DecisionActor::trusted_ui
                       ? "trusted-ui"
                       : "reviewed-policy") +
        ",\"decidedWallSeconds\":" +
        std::to_string(decision.decided_wall_seconds) + "}";
  }
  decisions += ']';
  return "{\"schemaVersion\":" + std::to_string(state.schema_version) +
         ",\"securePluginSchemaVersion\":2,\"legacySchemaV1Safe\":false," +
         "\"mutationSequence\":" + std::to_string(state.mutation_sequence) +
         ",\"nextDecisionSequence\":" +
         std::to_string(state.next_decision_sequence) +
         ",\"plugins\":" + plugins + ",\"decisions\":" + decisions + "}";
}

std::string preview_json(const Preview &preview) {
  std::string delta = "[";
  for (std::size_t index = 0; index < preview.request_delta.size(); ++index) {
    if (index > 0)
      delta += ',';
    const auto &entry = preview.request_delta[index];
    delta += "{\"capability\":" + key_json(entry.capability) +
             ",\"change\":" + json_quote(delta_name(entry.kind)) +
             ",\"inherited\":" +
             (entry.inherited_grant.has_value() ? "true" : "false") + "}";
  }
  delta += ']';
  return "{\"schemaVersion\":1,\"expectedMutationSequence\":" +
         std::to_string(preview.expected_mutation_sequence) +
         ",\"target\":" + json_quote(target_name(preview.target)) +
         ",\"plugin\":" + json_quote(preview.binding.plugin.view()) +
         ",\"revision\":" + json_quote(preview.binding.revision.view()) +
         ",\"policyFingerprint\":" +
         json_quote(preview.binding.policy_fingerprint.view()) +
         ",\"generation\":" + std::to_string(preview.binding.generation) +
         ",\"currentGrant\":" +
         (preview.current_grant ? grant_json(*preview.current_grant) : "null") +
         ",\"requestDelta\":" + delta + "}";
}

std::string mutation_json(const MutationResult &result) {
  return "{\"schemaVersion\":1,\"mutationSequence\":" +
         std::to_string(result.mutation_sequence) +
         ",\"decisionSequence\":" + std::to_string(result.decision_sequence) +
         ",\"target\":" + json_quote(target_name(result.target)) +
         ",\"grant\":" + grant_json(result.grant) +
         ",\"grantFingerprint\":" + json_quote(result.grant_fingerprint) + "}";
}

std::string revocation_json(const RevocationResult &result) {
  const auto action =
      result.action == permission::RevocationMode::deny_new ? "deny-new"
      : result.action == permission::RevocationMode::cancel_inflight
          ? "cancel-inflight"
          : "restart-worker";
  return "{\"schemaVersion\":1,\"mutationSequence\":" +
         std::to_string(result.mutation_sequence) +
         ",\"target\":" + json_quote(target_name(result.target)) +
         ",\"grant\":" + grant_json(result.grant) +
         ",\"revocationAction\":" + json_quote(action) +
         ",\"grantFingerprint\":" + json_quote(result.grant_fingerprint) + "}";
}

} // namespace omarchy::plugins::grants
