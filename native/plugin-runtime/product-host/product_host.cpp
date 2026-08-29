#include "product_host.hpp"

#include <QJsonDocument>
#include <QJsonArray>
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

const permissions::GrantRecord *find_grant_by_id(
    const grants::RevisionGrants &revision, std::string_view capability) {
  const auto values = revision.grants.values();
  const auto found = std::ranges::find_if(values, [&](const auto &grant) {
    return grant.capability.id.view() == capability;
  });
  return found == values.end() ? nullptr : &*found;
}

std::vector<std::byte> permission_snapshot_payload(
    const PreparedPlugin &prepared) {
  QJsonArray entries;
  for (const auto &item : prepared.permission_availability) {
    entries.append(QJsonObject{
        {QStringLiteral("capability"), QString::fromStdString(item.capability)},
        {QStringLiteral("operation"), QString::fromStdString(item.operation)},
        {QStringLiteral("granted"), item.granted}});
  }
  const auto json = QJsonDocument(QJsonObject{
      {QStringLiteral("generation"),
       static_cast<qint64>(prepared.binding.generation)},
      {QStringLiteral("permissions"), entries}})
                        .toJson(QJsonDocument::Compact);
  const auto bytes = std::as_bytes(
      std::span(json.constData(), static_cast<std::size_t>(json.size())));
  return {bytes.begin(), bytes.end()};
}

} // namespace

PreparedPlugin::PreparedPlugin(
    discovery::VerifiedPlugin verified,
    permissions::ActivationBinding activation,
    std::vector<surface_host::NamedSurfacePolicy> policies,
    std::vector<SurfaceEntrypoint> surface_entrypoints_value,
    std::vector<PermissionAvailability> permission_availability_value,
    int revision_fd)
    : plugin(std::move(verified)), binding(std::move(activation)),
      surfaces(std::move(policies)),
      surface_entrypoints(std::move(surface_entrypoints_value)),
      permission_availability(std::move(permission_availability_value)),
      revision_directory_fd(revision_fd) {}

PreparedPlugin::~PreparedPlugin() {
  if (revision_directory_fd >= 0)
    close(revision_directory_fd);
}

PreparedPlugin::PreparedPlugin(PreparedPlugin &&other) noexcept
    : plugin(std::move(other.plugin)), binding(std::move(other.binding)),
      surfaces(std::move(other.surfaces)),
      surface_entrypoints(std::move(other.surface_entrypoints)),
      permission_availability(std::move(other.permission_availability)),
      revision_directory_fd(std::exchange(other.revision_directory_fd, -1)) {}

PreparedPlugin &PreparedPlugin::operator=(PreparedPlugin &&other) noexcept {
  if (this != &other) {
    if (revision_directory_fd >= 0)
      close(revision_directory_fd);
    plugin = std::move(other.plugin);
    binding = std::move(other.binding);
    surfaces = std::move(other.surfaces);
    surface_entrypoints = std::move(other.surface_entrypoints);
    permission_availability = std::move(other.permission_availability);
    revision_directory_fd = std::exchange(other.revision_directory_fd, -1);
  }
  return *this;
}

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
      .policy_fingerprint = permissions::Digest(grants::request_policy_fingerprint(
          active_grants.requests, active_grants.dynamic_grants)),
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
  std::vector<PreparedPlugin::SurfaceEntrypoint> surface_entrypoints;
  std::vector<PreparedPlugin::PermissionAvailability> availability;
  for (const auto &request : found->manifest.requests) {
    std::vector<std::string> operations = request.operations;
    if (operations.empty() && request.capability == "storage.private")
      operations = {"read", "write", "remove"};
    else if (operations.empty() && request.capability == "notifications.send")
      operations = {"send"};
    else if (operations.empty() && request.capability == "audio.play-cue")
      operations = {"play"};
    else if (operations.empty() && request.capability == "service.fake-status")
      operations = {"list", "acknowledge"};
    const auto *grant = find_grant_by_id(active_grants, request.capability);
    const bool granted = grant != nullptr &&
                         grant->state == permissions::GrantState::granted;
    for (const auto &operation : operations) {
      const bool operation_granted =
          granted && (request.operations.empty() ||
                      std::ranges::find(request.operations, operation) !=
                          request.operations.end());
      availability.push_back({request.capability, operation,
                              operation_granted});
    }
  }
  const auto document = QJsonDocument::fromJson(
      QByteArray::fromStdString(found->manifest.canonical_json));
  const auto surface_object = document.object().value("surfaces").toObject();
  try {
    for (auto iterator = surface_object.begin(); iterator != surface_object.end();
         ++iterator) {
      surfaces.push_back(surface_host::parse_named_surface_policy(
          found->manifest, iterator.key().toStdString()));
      auto qml = found->manifest.runtime.qml;
      const auto entry = std::ranges::find_if(
          found->manifest.runtime.surface_qml, [&](const auto &candidate) {
            return candidate.surface == iterator.key().toStdString();
          });
      if (entry != found->manifest.runtime.surface_qml.end())
        qml = entry->qml;
      surface_entrypoints.push_back(
          {iterator.key().toStdString(), std::move(qml)});
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
  const int revision_fd =
      open(found->root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (revision_fd < 0) {
    return {.prepared = nullptr,
            .failure = PrepareFailure::discovery_rejected,
            .detail = "verified revision directory could not be pinned"};
  }
  return {.prepared = std::make_unique<PreparedPlugin>(
              *found, active_grants.binding, std::move(surfaces),
              std::move(surface_entrypoints),
              std::move(availability), revision_fd),
          .failure = PrepareFailure::none,
          .detail = {}};
}

MultiSurfaceActivation::MultiSurfaceActivation(const PreparedPlugin &prepared)
    : prepared_(prepared) {}

std::optional<std::string_view>
MultiSurfaceActivation::qml_entry(std::string_view surface) const {
  const auto found = std::ranges::find_if(
      prepared_.surface_entrypoints,
      [&](const auto &entry) { return entry.surface == surface; });
  if (found == prepared_.surface_entrypoints.end())
    return std::nullopt;
  return found->qml;
}

bool MultiSurfaceActivation::register_surface(
    std::string_view surface, std::uint64_t authenticated_session_nonce,
    const permissions::ActivationBinding &binding) {
  if (authenticated_session_nonce == 0 ||
      !same_binding(binding, prepared_.binding) || !qml_entry(surface))
    return false;
  const auto duplicate = std::ranges::find_if(
      registered_, [&](const auto &entry) {
        return entry.surface == surface ||
               entry.nonce == authenticated_session_nonce;
      });
  if (duplicate != registered_.end())
    return false;
  registered_.push_back(
      {std::string(surface), authenticated_session_nonce});
  return true;
}

std::optional<SurfaceCommand> MultiSurfaceActivation::route_intent(
    std::string_view source_surface,
    std::uint64_t authenticated_session_nonce,
    const permissions::ActivationBinding &binding,
    std::string_view target_surface, SurfaceIntentAction action,
    bool trusted_user_gesture) const {
  if (!same_binding(binding, prepared_.binding) || !qml_entry(target_surface))
    return std::nullopt;
  const auto source = std::ranges::find_if(
      registered_, [&](const auto &entry) {
        return entry.surface == source_surface &&
               entry.nonce == authenticated_session_nonce;
      });
  if (source == registered_.end())
    return std::nullopt;
  if ((action == SurfaceIntentAction::toggle ||
       action == SurfaceIntentAction::focus) &&
      !trusted_user_gesture)
    return std::nullopt;
  return SurfaceCommand{std::string(target_surface), action};
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
  return launch_with_broker_for_lab(
      supervisor, prepared, private_state_directory_fd, health,
      std::make_shared<DenyAllBroker>(prepared.binding), std::move(authority),
      now_seconds, negotiation_timeout);
}

headless::StartResult launch_with_broker_for_lab(
    launcher::Supervisor &supervisor, const PreparedPlugin &prepared,
    int private_state_directory_fd, health::HealthSupervisor &health,
    std::shared_ptr<channel::BrokerDispatcher> dispatcher,
    std::shared_ptr<const channel::GenerationAuthority> authority,
    std::uint64_t now_seconds,
    std::chrono::milliseconds negotiation_timeout) {
  if (dispatcher == nullptr ||
      !dispatcher->accepts({.plugin_id = std::string(prepared.binding.plugin.view()),
                            .revision_sha256 = std::string(prepared.binding.revision.view()),
                            .generation = prepared.binding.generation})) {
    return {.session = nullptr,
            .failure = headless::StartFailure::invalid_binding,
            .detail = "lab broker does not accept the prepared activation"};
  }
  const int revision_fd =
      fcntl(prepared.revision_directory_fd, F_DUPFD_CLOEXEC, 64);
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
  auto started = headless::Session::start(
      supervisor, request, prepared.binding, health, std::move(dispatcher),
      std::move(authority), now_seconds, negotiation_timeout);
  if (started && !update_permission_availability(*started.session, prepared)) {
    const auto diagnostic = started.session->take_worker_standard_error();
    (void)started.session->stop();
    return {.session = nullptr,
            .failure = headless::StartFailure::readiness,
            .detail = diagnostic.empty()
                          ? "initial permission snapshot delivery failed"
                          : "initial permission snapshot delivery failed: " +
                                diagnostic};
  }
  return started;
}

bool update_permission_availability(headless::Session &session,
                                    const PreparedPlugin &prepared) {
  if (session.binding().plugin != prepared.binding.plugin ||
      session.binding().revision != prepared.binding.revision ||
      session.binding().policy_fingerprint !=
          prepared.binding.policy_fingerprint ||
      session.binding().generation != prepared.binding.generation)
    return false;
  const auto payload = permission_snapshot_payload(prepared);
  return session.send_control(omarchy::plugin::wire::kPermissionSnapshotMessage,
                              payload) &&
         session.receive_control_ack(
             omarchy::plugin::wire::kPermissionSnapshotAcceptedMessage,
             std::chrono::seconds(5));
}

} // namespace omarchy::plugin_runtime::product_host
