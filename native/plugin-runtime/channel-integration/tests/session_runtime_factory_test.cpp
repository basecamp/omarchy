#include "session_runtime_factory.hpp"

#include "omarchy/plugin_runtime/broker/broker_schema.hpp"
#include "structured_broker.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <mutex>
#include <stdexcept>
#include <thread>

namespace channel = omarchy::plugin_runtime::channel;
namespace definitions = omarchy::plugins::definitions;
namespace host = omarchy::plugin_runtime::host_session;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace policy = omarchy::plugin_runtime::policy;
namespace runtime = omarchy::plugin_runtime::runtime;
namespace wire = omarchy::plugin::wire;
namespace broker = omarchy::plugin_runtime::broker;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

permissions::Digest digest(char value) {
  return permissions::Digest(std::string(64, value));
}

permissions::TokenScope tokens(std::string_view token) {
  permissions::TokenScope scope;
  require(scope.tokens.insert(permissions::ScopeToken(token)),
          "duplicate token fixture");
  return scope;
}

struct Directories final {
  std::filesystem::path root;
  int revision = -1;
  int state = -1;

  Directories() {
    std::string pattern =
        (std::filesystem::temp_directory_path() / "omarchy-runtime-XXXXXX")
            .string();
    pattern.push_back('\0');
    const auto created = ::mkdtemp(pattern.data());
    require(created != nullptr, "runtime fixture root creation failed");
    root = created;
    require(::mkdir((root / "revision").c_str(), 0700) == 0 &&
                ::mkdir((root / "state").c_str(), 0700) == 0,
            "runtime fixture directories failed");
    revision = ::open((root / "revision").c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    state = ::open((root / "state").c_str(),
                   O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    require(revision >= 0 && state >= 0, "runtime fixture open failed");
  }

  ~Directories() {
    if (revision >= 0)
      ::close(revision);
    if (state >= 0)
      ::close(state);
    std::error_code ignored;
    std::filesystem::remove_all(root, ignored);
  }
};

class Clock final : public runtime::GestureEligibilityClock {
public:
  [[nodiscard]] std::uint64_t now_nanoseconds() const override { return 1; }
};

std::shared_ptr<runtime::GestureEligibilityLatch> gesture() {
  return std::make_shared<runtime::GestureEligibilityLatch>(
      std::make_shared<Clock>());
}

std::shared_ptr<const omarchy::plugin_runtime::provider_host::ProviderCatalog>
empty_provider_catalog(const std::filesystem::path &root) {
  require(::mkdir((root / "provider-package").c_str(), 0700) == 0 &&
              ::mkdir((root / "provider-admin").c_str(), 0700) == 0,
          "empty provider roots failed");
  const int root_fd =
      ::open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  require(root_fd >= 0, "empty provider root open failed");
  const std::array<std::string_view, 1> package{"provider-package"};
  const std::array<std::string_view, 1> admin{"provider-admin"};
  omarchy::plugin_runtime::provider_host::CatalogError error{};
  auto catalog =
      omarchy::plugin_runtime::provider_host::ProviderCatalog::load(
          root_fd, package, admin, static_cast<std::uint32_t>(::getuid()), error);
  ::close(root_fd);
  require(catalog && error ==
                         omarchy::plugin_runtime::provider_host::CatalogError::none,
          "empty provider catalog load failed");
  return catalog;
}

policy::GrantSnapshot audio_snapshot() {
  policy::GrantSnapshot snapshot;
  const permissions::CapabilityKey capability{
      .id = permissions::CapabilityId("audio.play-cue"), .version = 1};
  snapshot.requests.push_back({.capability = capability,
                               .scope = tokens("complete"),
                               .required = true});
  snapshot.binding = {
      .plugin = permissions::PluginId("fixture.plugin"),
      .revision = digest('a'),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = 7};
  snapshot.grants.push_back({.capability = capability,
                             .scope = tokens("complete"),
                             .state = permissions::GrantState::granted,
                             .epoch = 7});
  return snapshot;
}

policy::GrantSnapshot storage_snapshot(std::uint64_t total,
                                       std::uint64_t item) {
  policy::GrantSnapshot snapshot;
  const permissions::CapabilityKey capability{
      .id = permissions::CapabilityId("storage.private"), .version = 1};
  const permissions::QuotaScope quota{.total_bytes = total,
                                       .item_bytes = item};
  snapshot.requests.push_back(
      {.capability = capability, .scope = quota, .required = true});
  snapshot.binding = {
      .plugin = permissions::PluginId("fixture.plugin"),
      .revision = digest('a'),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = 7};
  snapshot.grants.push_back({.capability = capability,
                             .scope = quota,
                             .state = permissions::GrantState::granted,
                             .epoch = 7});
  return snapshot;
}

manifest::ManifestV2 plugin_manifest() {
  manifest::ManifestV2 value;
  value.id = "fixture.plugin";
  return value;
}

void put16(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

void put64(std::vector<std::byte> &bytes, std::size_t offset,
           std::uint64_t value) {
  for (std::size_t index = 0; index < 8; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((7U - index) * 8U));
}

std::vector<std::byte> audio_request() {
  constexpr std::string_view cue = "complete";
  std::vector<std::byte> bytes(10 + cue.size());
  put16(bytes, 0,
        static_cast<std::uint16_t>(permissions::OperationId::audio_play_cue));
  put16(bytes, 2, static_cast<std::uint16_t>(2 + cue.size()));
  put32(bytes, 4, 0);
  put16(bytes, 8, static_cast<std::uint16_t>(cue.size()));
  for (std::size_t index = 0; index < cue.size(); ++index)
    bytes[10 + index] = static_cast<std::byte>(cue[index]);
  return bytes;
}

std::vector<std::byte> storage_write_request(std::string_view key,
                                             std::span<const std::byte> value,
                                             std::uint64_t total,
                                             std::uint64_t item) {
  std::vector<std::byte> body(6 + key.size() + value.size());
  put16(body, 0, static_cast<std::uint16_t>(key.size()));
  put32(body, 2, static_cast<std::uint32_t>(value.size()));
  for (std::size_t index = 0; index < key.size(); ++index)
    body[6 + index] = static_cast<std::byte>(key[index]);
  std::copy(value.begin(), value.end(), body.begin() + 6 + key.size());
  std::vector<std::byte> request(24 + body.size());
  put16(request, 0,
        static_cast<std::uint16_t>(permissions::OperationId::storage_write));
  put16(request, 2, 16);
  put32(request, 4, static_cast<std::uint32_t>(body.size()));
  put64(request, 8, total);
  put64(request, 16, item);
  std::copy(body.begin(), body.end(), request.begin() + 24);
  return request;
}

struct ServiceProbe final {
  std::size_t audio_calls = 0;
  std::size_t dynamic_calls = 0;
};

struct BlockingProbe final {
  std::mutex mutex;
  std::condition_variable changed;
  bool entered = false;
  bool release = false;
  std::size_t calls = 0;
};

bool blocking_audio(std::string_view, void *context) noexcept {
  auto &probe = *static_cast<BlockingProbe *>(context);
  std::unique_lock lock(probe.mutex);
  ++probe.calls;
  probe.entered = true;
  probe.changed.notify_all();
  probe.changed.wait(lock, [&] { return probe.release; });
  return true;
}

bool play_audio(std::string_view cue, void *context) noexcept {
  auto &probe = *static_cast<ServiceProbe *>(context);
  ++probe.audio_calls;
  return cue == "complete";
}

definitions::DynamicScopeRelation exact_scope(
    const definitions::CapabilityDefinition &, std::string_view candidate,
    std::string_view baseline, void *) noexcept {
  return candidate == baseline ? definitions::DynamicScopeRelation::equal
                               : definitions::DynamicScopeRelation::expanded;
}

bool dynamic_dispatch(const definitions::AuthorizedDynamicRequest &,
                      std::span<std::byte>, std::size_t &written,
                      void *context) noexcept {
  ++static_cast<ServiceProbe *>(context)->dynamic_calls;
  written = 0;
  return true;
}

definitions::CapabilityDefinition dynamic_definition() {
  definitions::CapabilityDefinition definition{
      .canonical_name = definitions::Name("service.echo"),
      .authority_identity = definitions::Name("service.echo.authority"),
      .enforcement_family = definitions::EnforcementFamily::network_fetch,
      .display_category_id = definitions::Name("developer.services"),
      .display_category_label = definitions::Label("Developer services"),
      .scope_schema = definitions::ScopeSchema::https_origins_and_methods,
      .title = definitions::Label("Echo"),
      .risk_text = definitions::Label("Uses trusted echo service"),
      .risk = definitions::RiskLevel::moderate,
      .revocation = definitions::RevocationPolicy::deny_new,
      .audit = {},
      .adapter = {.adapter_class = definitions::Name("service.echo.adapter"),
                  .contract_digest = digest('d'),
                  .abi_version = 1},
      .operations = {}};
  definition.operations.insert(
      {.name = definitions::Name("echo"),
       .label = definitions::Label("Echo payload")});
  return definition;
}

policy::GrantSnapshot dynamic_snapshot(
    const definitions::ResolvedDefinition &resolved,
    permissions::GrantState state = permissions::GrantState::granted,
    bool required = false) {
  manifest::ManifestV2 manifest_value;
  manifest_value.id = "fixture.plugin";
  manifest_value.requests.push_back(
      {.capability = std::string(resolved.definition->canonical_name.view()),
       .reason = "exercise an exact trusted provider",
       .canonical_scope = "exact",
       .definition_generation = resolved.generation,
       .definition_digest = std::string(resolved.digest.view()),
       .operations = {"echo"},
       .required = required});
  policy::GrantSnapshot snapshot;
  snapshot.requests = permissions::requests_from_manifest(manifest_value);
  snapshot.binding = {
      .plugin = permissions::PluginId("fixture.plugin"),
      .revision = digest('a'),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(snapshot.requests)),
      .generation = 7};
  snapshot.source_request_fingerprint = permissions::Digest(
      manifest::requested_capability_fingerprint(manifest_value.requests));
  definitions::DynamicRevisionGrant grant{
      .binding = snapshot.binding,
      .request = {.definition =
                      {.canonical_name = resolved.definition->canonical_name,
                       .definition_generation = resolved.generation,
                       .definition_digest = resolved.digest},
                  .operations = {},
                  .scope = definitions::CanonicalScope("exact"),
                  .required = required},
      .grant = {}};
  grant.request.operations.insert(definitions::Name("echo"));
  grant.grant = {.definition = grant.request.definition,
                 .operations = grant.request.operations,
                 .scope = grant.request.scope,
                 .state = state,
                 .epoch = 7};
  snapshot.dynamic_grants.push_back(std::move(grant));
  return snapshot;
}

manifest::ManifestV2
dynamic_manifest(const definitions::ResolvedDefinition &resolved,
                 bool required = false) {
  manifest::ManifestV2 value;
  value.id = "fixture.plugin";
  value.requests.push_back(
      {.capability = std::string(resolved.definition->canonical_name.view()),
       .reason = "exercise an exact trusted provider",
       .canonical_scope = "exact",
       .definition_generation = resolved.generation,
       .definition_digest = std::string(resolved.digest.view()),
       .operations = {"echo"},
       .required = required});
  return value;
}

void provider_completeness_and_effect_fence() {
  Directories directories;
  definitions::TrustedDefinitionRegistry definitions;
  auto grants = audio_snapshot();
  auto live = std::make_shared<host::LiveGenerationState>(grants.binding);
  channel::SessionRuntimeFactory missing(definitions, {});
  require(!missing.create(plugin_manifest(), grants, directories.revision,
                          directories.state, 41, live, gesture()),
          "granted audio accepted a missing host service");

  auto probe = std::make_shared<ServiceProbe>();
  std::weak_ptr<ServiceProbe> retained = probe;
  channel::RuntimeServices services{
      .context = probe,
      .notification_send = nullptr,
      .audio_play = play_audio,
      .compare_scope = nullptr,
      .dynamic_services = {}, .provider_catalog = {}};
  auto factory = std::make_unique<channel::SessionRuntimeFactory>(
      definitions, services);
  auto product = factory->create(plugin_manifest(), grants,
                                 directories.revision, directories.state, 41,
                                 live, gesture());
  require(product && product->broker().accepts(grants.binding, 41),
          "complete audio runtime was not constructed");
  probe.reset();
  services.context.reset();
  factory.reset();
  require(!retained.expired(), "runtime did not retain trusted services");

  auto admission = product->broker().take_admission();
  require(static_cast<bool>(admission), "runtime admission unavailable");
  const auto payload = audio_request();
  auto first = admission.admission->admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::audio_play_cue),
       .correlation_id = 1,
       .payload = payload});
  require(static_cast<bool>(first), "audio request was not admitted");
  std::array<std::byte, 64> response{};
  auto allowed = product->broker().dispatch(std::move(*first.request), 1,
                                            response);
  require(allowed.state() == host::TransactionState::reply &&
              retained.lock()->audio_calls == 1,
          "audio effect did not use the trusted synchronous service");
  require(product->broker().commit_sent(std::move(allowed)),
          "audio transaction did not settle");
  (void)live->revoke_and_drain();
  auto second = admission.admission->admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::audio_play_cue),
       .correlation_id = 2,
       .payload = payload});
  require(static_cast<bool>(second), "revoked audio request was not admitted");
  auto fenced = product->broker().dispatch(std::move(*second.request), 2,
                                           response);
  require(fenced.state() == host::TransactionState::fatal &&
              retained.lock()->audio_calls == 1,
          "revoked live generation reached a provider effect");
  product.reset();
  require(retained.expired(), "runtime leaked trusted service ownership");
}

void descriptor_quota_and_dynamic_catalog_validation() {
  Directories directories;
  definitions::TrustedDefinitionRegistry empty;
  auto storage = storage_snapshot(4096, 1024);
  auto live = std::make_shared<host::LiveGenerationState>(storage.binding);
  channel::SessionRuntimeFactory constrained(
      empty, {}, {.maximum_audit_records = 8,
                  .maximum_storage_bytes = 2048,
                  .maximum_storage_item_bytes = 1024});
  require(!constrained.create(plugin_manifest(), storage, directories.revision,
                              directories.state, 42, live, gesture()),
          "granted storage quota exceeded the host ceiling");
  channel::SessionRuntimeFactory exact(
      empty, {}, {.maximum_audit_records = 8,
                  .maximum_storage_bytes = 4096,
                  .maximum_storage_item_bytes = 1024});
  require(!exact.create(plugin_manifest(), storage, directories.revision, -1,
                        42, live, gesture()),
          "closed private-state descriptor constructed storage");
  auto storage_product = exact.create(plugin_manifest(), storage,
                                      directories.revision, directories.state,
                                      42, live, gesture());
  require(storage_product != nullptr,
          "exact descriptor-rooted storage runtime was rejected");
  auto storage_admission = storage_product->broker().take_admission();
  require(static_cast<bool>(storage_admission),
          "storage runtime admission unavailable");
  const std::array value{std::byte{0xaa}, std::byte{0xbb}};
  const auto storage_payload =
      storage_write_request("proof", value, 4096, 1024);
  auto storage_request = storage_admission.admission->admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::storage_write),
       .correlation_id = 1,
       .payload = storage_payload});
  require(static_cast<bool>(storage_request),
          "storage write request was not admitted");
  std::array<std::byte, 64> storage_response{};
  auto storage_result = storage_product->broker().dispatch(
      std::move(*storage_request.request), 1, storage_response);
  require(storage_result.state() == host::TransactionState::reply &&
              storage_product->broker().commit_sent(
                  std::move(storage_result)),
          "descriptor-rooted storage write did not settle");
  const int proof = ::openat(directories.state, "proof",
                             O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  std::array<std::byte, 2> stored{};
  require(proof >= 0 && ::read(proof, stored.data(), stored.size()) == 2 &&
              stored == value,
          "storage backend did not write through the pinned state descriptor");
  if (proof >= 0)
    ::close(proof);

  definitions::TrustedDefinitionRegistry mutable_definitions;
  const auto definition = dynamic_definition();
  require(mutable_definitions.install(
              definition, definitions::DefinitionSource::omarchy_package, 3),
          "dynamic definition install failed");
  const auto resolved = mutable_definitions.find("service.echo");
  require(resolved.has_value(), "dynamic definition lookup failed");
  auto dynamic = dynamic_snapshot(*resolved);
  const auto dynamic_plugin = dynamic_manifest(*resolved);
  auto dynamic_live =
      std::make_shared<host::LiveGenerationState>(dynamic.binding);
  auto probe = std::make_shared<ServiceProbe>();
  channel::RuntimeServices missing_route{
      .context = probe,
      .notification_send = nullptr,
      .audio_play = nullptr,
      .compare_scope = exact_scope,
      .dynamic_services = {},
      .provider_catalog = empty_provider_catalog(directories.root)};
  channel::SessionRuntimeFactory missing_dynamic(
      mutable_definitions, missing_route);
  auto missing_product = missing_dynamic.create(
      dynamic_plugin, dynamic, directories.revision, directories.state, 43,
      dynamic_live, gesture());
  const auto missing_projection =
      missing_dynamic.project_permissions(dynamic_plugin, dynamic);
  require(missing_product && missing_projection &&
              missing_projection->permissions.size() == 1 &&
              missing_projection->permissions[0].state ==
                  wire::permission_snapshot::GrantState::granted &&
              missing_projection->permissions[0].operation_mask == 0,
          "optional granted permission did not degrade without its provider");
  auto required_dynamic =
      dynamic_snapshot(*resolved, permissions::GrantState::granted, true);
  const auto required_plugin = dynamic_manifest(*resolved, true);
  auto required_live =
      std::make_shared<host::LiveGenerationState>(required_dynamic.binding);
  require(!missing_dynamic.create(required_plugin, required_dynamic,
                                  directories.revision, directories.state, 44,
                                  required_live, gesture()) &&
              !missing_dynamic.project_permissions(required_plugin,
                                                   required_dynamic),
          "required granted permission activated without its provider");
  missing_route.provider_catalog.reset();
  auto wrong = definition.adapter;
  wrong.contract_digest = digest('e');
  missing_route.dynamic_services.push_back(
      {.binding = wrong, .dispatch = dynamic_dispatch});
  channel::SessionRuntimeFactory wrong_dynamic(
      mutable_definitions, missing_route);
  require(wrong_dynamic.create(dynamic_plugin, dynamic, directories.revision,
                               directories.state, 43, dynamic_live,
                               gesture()) != nullptr,
          "optional permission did not degrade for a wrong provider digest");
  missing_route.dynamic_services[0].binding = definition.adapter;
  missing_route.dynamic_services.push_back(
      {.binding = definition.adapter, .dispatch = dynamic_dispatch});
  channel::SessionRuntimeFactory duplicate_dynamic(
      mutable_definitions, missing_route);
  require(duplicate_dynamic.create(dynamic_plugin, dynamic,
                                   directories.revision, directories.state, 43,
                                   dynamic_live, gesture()) != nullptr,
          "optional permission did not degrade for ambiguous providers");
  missing_route.dynamic_services.pop_back();
  missing_route.dynamic_services[0].binding.abi_version = 2;
  channel::SessionRuntimeFactory wrong_abi_dynamic(
      mutable_definitions, missing_route);
  require(wrong_abi_dynamic.create(dynamic_plugin, dynamic,
                                   directories.revision, directories.state, 43,
                                   dynamic_live, gesture()) != nullptr,
          "optional permission did not degrade for a wrong provider ABI");
  missing_route.dynamic_services[0].binding = definition.adapter;
  channel::SessionRuntimeFactory exact_dynamic(
      mutable_definitions, missing_route);
  const auto restored_projection =
      exact_dynamic.project_permissions(dynamic_plugin, dynamic);
  require(restored_projection && restored_projection->permissions.size() == 1 &&
              restored_projection->permissions[0] ==
                  wire::permission_snapshot::PermissionRow{
                      wire::permission_snapshot::GrantState::granted, 0x0001},
          "the exact provider did not restore an existing durable grant");
  auto changed_definition = dynamic_definition();
  changed_definition.canonical_name = definitions::Name("service.other");
  changed_definition.authority_identity =
      definitions::Name("service.other.authority");
  changed_definition.adapter.adapter_class =
      definitions::Name("service.other.adapter");
  require(mutable_definitions.install(
              changed_definition,
              definitions::DefinitionSource::omarchy_package, 4),
          "source registry mutation failed");
  require(mutable_definitions.find("service.other").has_value() &&
              !exact_dynamic.definitions().find("service.other") &&
              exact_dynamic.definitions().size() == 1,
          "factory registry changed through its mutable source alias");
  auto dynamic_product = exact_dynamic.create(
      dynamic_plugin, dynamic, directories.revision, directories.state, 43,
      dynamic_live, gesture());
  require(dynamic_product != nullptr,
          "exact trusted dynamic route was rejected");
  auto dynamic_admission = dynamic_product->broker().take_admission();
  require(static_cast<bool>(dynamic_admission),
          "dynamic runtime admission unavailable");
  definitions::DynamicInvocation invocation{
      .definition = dynamic.dynamic_grants[0].request.definition,
      .operation = definitions::Name("echo"),
      .demand_scope = definitions::CanonicalScope("exact"),
      .gesture = std::nullopt,
      .payload = {}};
  std::vector<std::byte> dynamic_payload(
      definitions::kMaximumDynamicEnvelopeBytes);
  std::size_t dynamic_size = 0;
  require(definitions::encode_dynamic_invocation(invocation, dynamic_payload,
                                                 dynamic_size),
          "dynamic invocation encoding failed");
  dynamic_payload.resize(dynamic_size);
  auto missing_admission = missing_product->broker().take_admission();
  require(static_cast<bool>(missing_admission),
          "missing-provider runtime admission unavailable");
  auto missing_request = missing_admission.admission->admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 9,
       .payload = dynamic_payload});
  require(static_cast<bool>(missing_request),
          "missing-provider request was not admitted for broker rejection");
  std::array<std::byte, 64> missing_response{};
  auto missing_result = missing_product->broker().dispatch(
      std::move(*missing_request.request), 9, missing_response);
  // The trusted snapshot gives well-behaved QML a zero operation mask. If a
  // compromised worker bypasses that local gate, the broker returns a typed
  // denial for the absent route and never reaches a provider callback. This
  // is nonfatal so a transient provider outage cannot kill unrelated plugin
  // features.
  require(missing_result.state() == host::TransactionState::reply &&
              missing_result.reply_kind() == host::ReplyKind::denied &&
              probe->dynamic_calls == 0 &&
              missing_product->broker().commit_sent(std::move(missing_result)),
          "missing optional provider received a call");
  auto dynamic_request = dynamic_admission.admission->admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 1,
       .payload = dynamic_payload});
  require(static_cast<bool>(dynamic_request),
          "dynamic request was not admitted");
  std::array<std::byte, 64> dynamic_response{};
  auto dynamic_result = dynamic_product->broker().dispatch(
      std::move(*dynamic_request.request), 1, dynamic_response);
  require(dynamic_result.state() == host::TransactionState::reply &&
              probe->dynamic_calls == 1 &&
              dynamic_product->broker().commit_sent(
                  std::move(dynamic_result)),
          "exact trusted dynamic callback did not settle once");

  auto denied = dynamic_snapshot(*resolved, permissions::GrantState::denied);
  auto denied_live =
      std::make_shared<host::LiveGenerationState>(denied.binding);
  channel::SessionRuntimeFactory denied_dynamic(
      mutable_definitions, {});
  require(denied_dynamic.create(dynamic_plugin, denied,
                                directories.revision, directories.state, 44,
                                denied_live, gesture()) != nullptr,
          "denied dynamic permission required an adapter or validator");

  channel::RuntimeServices provider_appeared{
      .context = probe,
      .notification_send = nullptr,
      .audio_play = nullptr,
      .compare_scope = exact_scope,
      .dynamic_services = {
          {.binding = definition.adapter, .dispatch = dynamic_dispatch}},
      .provider_catalog = {}};
  channel::SessionRuntimeFactory still_denied(
      mutable_definitions, provider_appeared);
  const auto denied_projection =
      still_denied.project_permissions(dynamic_plugin, denied);
  auto degraded = still_denied.create(
      dynamic_plugin, denied, directories.revision, directories.state, 45,
      denied_live, gesture());
  require(degraded && denied_projection &&
              denied_projection->permissions.size() == 1 &&
              denied_projection->permissions[0] ==
                  wire::permission_snapshot::PermissionRow{
                      wire::permission_snapshot::GrantState::denied, 0x0000},
          "provider appearance changed an explicitly denied activation");
  auto degraded_admission = degraded->broker().take_admission();
  require(static_cast<bool>(degraded_admission),
          "degraded runtime admission unavailable");
  auto denied_request = degraded_admission.admission->admit(
      {.message_type = broker::kDynamicInvokeMessage,
       .correlation_id = 2,
       .payload = dynamic_payload});
  require(static_cast<bool>(denied_request),
          "denied dynamic request was not admitted for broker rejection");
  auto denied_result = degraded->broker().dispatch(
      std::move(*denied_request.request), 2, dynamic_response);
  require(denied_result.state() == host::TransactionState::reply &&
              denied_result.reply_kind() == host::ReplyKind::denied &&
              probe->dynamic_calls == 1 &&
              degraded->broker().commit_sent(std::move(denied_result)),
          "a provider appearing later auto-granted or received a denied call");
}

void synchronous_effects_drain_before_revocation_acknowledges() {
  using namespace std::chrono_literals;
  Directories directories;
  definitions::TrustedDefinitionRegistry definitions;
  auto grants = audio_snapshot();

  auto reentrant =
      std::make_shared<host::LiveGenerationState>(grants.binding);
  auto token = reentrant->acquire_effect(grants.binding);
  require(token &&
              reentrant->revoke_and_drain() ==
                  host::LiveGenerationRevokeResult::reentrant &&
              !reentrant->current(grants.binding),
          "same-effect revocation deadlocked or acknowledged a drain");
  auto unrelated =
      std::make_shared<host::LiveGenerationState>(grants.binding);
  require(unrelated->revoke_and_drain() ==
              host::LiveGenerationRevokeResult::drained,
          "unrelated live state was mistaken for reentrant authority");
  token.reset();

  auto transferred =
      std::make_shared<host::LiveGenerationState>(grants.binding);
  auto acquired = transferred->acquire_effect(grants.binding);
  require(acquired.has_value(), "cross-thread effect acquisition failed");
  bool transferred_current = false;
  host::LiveGenerationRevokeResult transferred_revoke{};
  std::thread destination(
      [effect = std::move(*acquired), transferred, &transferred_current,
       &transferred_revoke]() mutable {
        transferred_current = effect.current();
        transferred_revoke = transferred->revoke_and_drain();
      });
  destination.join();
  require(transferred_current &&
              transferred_revoke ==
                  host::LiveGenerationRevokeResult::reentrant,
          "moved effect token lost its executing-thread reentry identity");

  auto live = std::make_shared<host::LiveGenerationState>(grants.binding);
  auto probe = std::make_shared<BlockingProbe>();
  channel::SessionRuntimeFactory factory(
      definitions,
      {.context = probe,
       .notification_send = nullptr,
       .audio_play = blocking_audio,
       .compare_scope = nullptr,
       .dynamic_services = {},
       .provider_catalog = {}});
  auto product = factory.create(plugin_manifest(), grants, directories.revision,
                                directories.state, 45, live, gesture());
  require(product != nullptr, "blocking effect runtime was rejected");
  auto admission = product->broker().take_admission();
  require(static_cast<bool>(admission), "blocking admission unavailable");
  const auto payload = audio_request();
  auto admitted = admission.admission->admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::audio_play_cue),
       .correlation_id = 1,
       .payload = payload});
  require(static_cast<bool>(admitted), "blocking effect was not admitted");

  std::array<std::byte, 64> response{};
  std::atomic<host::TransactionState> transaction_state{
      host::TransactionState::fatal};
  std::thread effect([&] {
    auto transaction = product->broker().dispatch(std::move(*admitted.request),
                                                   1, response);
    transaction_state.store(transaction.state(), std::memory_order_release);
    if (transaction.state() == host::TransactionState::reply)
      (void)product->broker().commit_sent(std::move(transaction));
  });
  {
    std::unique_lock lock(probe->mutex);
    require(probe->changed.wait_for(lock, 2s, [&] { return probe->entered; }),
            "blocking callback did not begin");
  }
  std::atomic<bool> revoked = false;
  host::LiveGenerationRevokeResult revoke_result{};
  std::thread revoker([&] {
    revoke_result = live->revoke_and_drain();
    revoked.store(true, std::memory_order_release);
  });
  for (int attempt = 0; attempt < 200 && live->generation() != 0; ++attempt)
    std::this_thread::sleep_for(1ms);
  require(live->generation() == 0 &&
              !revoked.load(std::memory_order_acquire),
          "revocation acknowledged before the in-flight effect drained");
  {
    std::scoped_lock lock(probe->mutex);
    probe->release = true;
  }
  probe->changed.notify_all();
  effect.join();
  revoker.join();
  require(revoke_result == host::LiveGenerationRevokeResult::drained &&
              transaction_state.load(std::memory_order_acquire) ==
                  host::TransactionState::reply &&
              probe->calls == 1,
          "revocation did not drain the exact synchronous effect");

  auto denied = admission.admission->admit(
      {.message_type = static_cast<std::uint16_t>(
           permissions::OperationId::audio_play_cue),
       .correlation_id = 2,
       .payload = payload});
  require(static_cast<bool>(denied), "post-revoke request was not admitted");
  auto fenced = product->broker().dispatch(std::move(*denied.request), 2,
                                           response);
  require(fenced.state() == host::TransactionState::fatal &&
              probe->calls == 1,
          "a provider effect began after revocation acknowledged");
}

} // namespace

void session_runtime_factory_tests() {
  provider_completeness_and_effect_fence();
  descriptor_quota_and_dynamic_catalog_validation();
  synchronous_effects_drain_before_revocation_acknowledges();
}
