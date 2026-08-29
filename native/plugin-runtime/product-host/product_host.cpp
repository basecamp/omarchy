#include "product_host.hpp"

#include <QJsonDocument>
#include <QJsonObject>

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <exception>
#include <utility>

namespace omarchy::plugin_runtime::product_host {
namespace {

bool same_binding(const permissions::ActivationBinding &left,
                  const permissions::ActivationBinding &right) {
  return left.plugin == right.plugin && left.revision == right.revision &&
         left.policy_fingerprint == right.policy_fingerprint &&
         left.generation == right.generation;
}

const permissions::GrantRecord *find_grant(
    const grants::RevisionGrants &revision,
    const permissions::CapabilityKey &capability) {
  const auto values = revision.grants.values();
  const auto found = std::ranges::find_if(values, [&](const auto &grant) {
    return grant.capability == capability;
  });
  return found == values.end() ? nullptr : &*found;
}

} // namespace

PrepareResult prepare(const std::filesystem::path &plugin_root,
                      const discovery::IdentityPin &identity_pin,
                      const grants::RevisionGrants &active_grants,
                      Configuration configuration) {
  if (!configuration.schema_v2_enabled) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::feature_disabled,
            .detail = "schema-v2 product host is disabled"};
  }
  const auto parent = plugin_root.parent_path();
  const auto report = discovery::discover(
      parent, std::span<const discovery::IdentityPin>(&identity_pin, 1),
      {.schema_v2_enabled = true});
  const auto directory = plugin_root.filename();
  const auto found = std::ranges::find_if(report.plugins, [&](const auto &item) {
    return item.root.filename() == directory;
  });
  if (found == report.plugins.end()) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::discovery_rejected,
            .detail = report.diagnostics.empty()
                          ? "verified plugin was not discovered"
                          : report.diagnostics.front().detail};
  }
  permissions::ActivationBinding expected{
      .plugin = permissions::PluginId(found->manifest.id),
      .revision = permissions::Digest(found->identity.tree_sha256),
      .policy_fingerprint = permissions::Digest(
          permissions::policy_request_fingerprint(active_grants.requests)),
      .generation = active_grants.binding.generation};
  if (!same_binding(expected, active_grants.binding) ||
      active_grants.source_request_fingerprint.view() !=
          found->identity.request_sha256) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::grant_binding_mismatch,
            .detail = "active grant binding does not match verified content"};
  }
  for (const auto &request : active_grants.requests.values()) {
    if (!request.required)
      continue;
    const auto *grant = find_grant(active_grants, request.capability);
    if (grant == nullptr || grant->state != permissions::GrantState::granted ||
        permissions::compare_scope(grant->scope, request.scope) ==
            permissions::ScopeRelation::expanded ||
        permissions::compare_scope(grant->scope, request.scope) ==
            permissions::ScopeRelation::incomparable) {
      return {.prepared = nullptr,
              .failure = PrepareFailure::required_grant_missing,
              .detail = "required capability lacks an explicit bounded grant"};
    }
  }

  std::vector<surface_host::NamedSurfacePolicy> surfaces;
  const auto document = QJsonDocument::fromJson(
      QByteArray::fromStdString(found->manifest.canonical_json));
  const auto surface_object = document.object().value("surfaces").toObject();
  try {
    for (auto iterator = surface_object.begin(); iterator != surface_object.end();
         ++iterator) {
      surfaces.push_back(surface_host::parse_named_surface_policy(
          found->manifest, iterator.key().toStdString()));
    }
  } catch (const std::exception &error) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::surface_invalid,
            .detail = error.what()};
  }
  if (surfaces.empty()) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::surface_invalid,
            .detail = "plugin declares no host-owned surface"};
  }
  return {.prepared = std::make_unique<PreparedPlugin>(PreparedPlugin{
              .plugin = *found,
              .binding = active_grants.binding,
              .surfaces = std::move(surfaces)}),
          .failure = PrepareFailure::none,
          .detail = {}};
}

DenyAllBroker::DenyAllBroker(permissions::ActivationBinding binding)
    : binding_(std::move(binding)) {}

bool DenyAllBroker::accepts(
    const launcher::LaunchIdentity &identity) const noexcept {
  return identity.plugin_id == binding_.plugin.view() &&
         identity.revision_sha256 == binding_.revision.view() &&
         identity.generation == binding_.generation;
}

bool DenyAllBroker::dispatch(const omarchy::plugin::wire::PacketView &) {
  return false;
}

headless::StartResult launch(
    launcher::Supervisor &supervisor, const PreparedPlugin &prepared,
    int private_state_directory_fd, health::HealthSupervisor &health,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout) {
  const int revision_fd = open(prepared.plugin.root.c_str(),
                               O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (revision_fd < 0) {
    return {.session = nullptr,
            .failure = headless::StartFailure::invalid_binding,
            .detail = "verified revision directory could not be opened"};
  }
  struct OwnedFd {
    int value;
    ~OwnedFd() { close(value); }
  } owned{revision_fd};
  launcher::TrustedLaunchRequest request{
      .plugin_id = std::string(prepared.binding.plugin.view()),
      .revision_sha256 = std::string(prepared.binding.revision.view()),
      .generation = prepared.binding.generation,
      .revision_directory_fd = revision_fd,
      .private_state_directory_fd = private_state_directory_fd};
  return headless::Session::start(
      supervisor, request, prepared.binding, health,
      std::make_shared<DenyAllBroker>(prepared.binding), std::move(authority),
      now_seconds, negotiation_timeout);
}

} // namespace omarchy::plugin_runtime::product_host
