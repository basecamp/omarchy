#pragma once

#include "audit_store.hpp"
#include "grant_store.hpp"
#include "omarchy/plugin_runtime/broker/broker_core.hpp"
#include "omarchy/plugin_runtime/providers/provider_set.hpp"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::runtime {

namespace audit = omarchy::plugins::audit;
namespace broker = omarchy::plugin_runtime::broker;
namespace grant = omarchy::plugins::grants;
namespace permissions = omarchy::plugins::permissions;
namespace providers = omarchy::plugin_runtime::providers;
namespace wire = omarchy::plugin::wire;

inline constexpr std::size_t kMaximumRuntimeRequests = 32;
inline constexpr std::size_t kMaximumRuntimeHandles = 32;
inline constexpr std::size_t kMaximumFakeResultBytes =
    4 + providers::kMaximumFakeStatuses *
            (10 + providers::kMaximumFakeStatusTextBytes);

enum class RuntimeStatus : std::uint8_t {
  accepted,
  denied,
  failed,
  unknown,
  audit_failed,
  binding_mismatch,
};

struct HandleResult {
  RuntimeStatus status = RuntimeStatus::failed;
  permissions::HandleDecision decision = permissions::HandleDecision::invalid;
};

struct RevocationResult {
  RuntimeStatus status = RuntimeStatus::failed;
  std::array<std::uint64_t, kMaximumRuntimeRequests> cancelled{};
  std::size_t cancelled_count = 0;
  bool restart_worker = false;
};

class AuditedBrokerRuntime {
public:
  AuditedBrokerRuntime(grant::RevisionGrants revision,
                       providers::ProviderConfiguration providers,
                       audit::AuditStore &audit_store);
  AuditedBrokerRuntime(const AuditedBrokerRuntime &) = delete;
  AuditedBrokerRuntime &operator=(const AuditedBrokerRuntime &) = delete;

  [[nodiscard]] broker::DispatchResult
  dispatch(const wire::PacketView &packet, std::uint64_t now_monotonic_ns,
           std::span<std::byte> response = {},
           permissions::GestureProof *gesture = nullptr);
  [[nodiscard]] broker::CancelResult
  accept_cancel(const wire::PacketView &packet);
  [[nodiscard]] broker::CancelResult
  accept_cancel_result(const wire::PacketView &packet);
  [[nodiscard]] broker::TerminalResult
  accept_terminal(const wire::PacketView &packet);

  [[nodiscard]] RevocationResult
  apply_revocation(const grant::RevocationResult &revocation);
  [[nodiscard]] RuntimeStatus shutdown();

  [[nodiscard]] HandleResult issue_handle(const permissions::HandleId &id,
                                          std::uint64_t correlation,
                                          permissions::OperationId operation,
                                          const permissions::Scope &scope,
                                          std::uint64_t expires_monotonic_ns);
  [[nodiscard]] HandleResult resolve_handle(const permissions::HandleId &id,
                                            std::uint64_t audit_correlation,
                                            permissions::OperationId operation,
                                            const permissions::Scope &scope,
                                            std::uint64_t now_monotonic_ns);

  [[nodiscard]] bool add_fake_status(std::uint32_t resource,
                                     std::uint32_t status,
                                     std::string_view text) noexcept;
  [[nodiscard]] providers::CompletionResult
  complete_fake_list(std::uint64_t correlation, std::span<std::byte> output,
                     std::size_t &bytes_written);

  [[nodiscard]] bool failed() const { return failed_ || core_.failed(); }
  [[nodiscard]] const permissions::ActivationBinding &binding() const {
    return binding_;
  }
  [[nodiscard]] const grant::RevisionGrants &revision() const {
    return revision_;
  }

private:
  struct TrackedRequest {
    std::uint64_t correlation = 0;
    permissions::OperationId operation{};
    permissions::CapabilityKey capability;
    permissions::Scope demand;
    std::uint64_t grant_epoch = 0;
    permissions::GrantDecisionCode decision =
        permissions::GrantDecisionCode::ungranted;
    bool authorized = false;
    bool cancel_requested = false;
    bool terminal_received = false;
    bool occupied = false;
  };

  struct GateContext {
    AuditedBrokerRuntime *owner = nullptr;
    broker::ProviderEntry provider;
  };

  struct GateRegistry {
    explicit GateRegistry(const broker::ProviderRegistry<7> &providers);
    std::array<GateContext, 7> contexts{};
    broker::ProviderRegistry<7> registry;
  };

  [[nodiscard]] static providers::ProviderConfiguration
  normalize_configuration(const grant::RevisionGrants &revision,
                          providers::ProviderConfiguration configuration);

  static broker::ProviderResult gate_dispatch(const broker::AuthorizedRequest &,
                                              std::span<std::byte>,
                                              void *) noexcept;
  static bool gate_cancel(std::uint64_t correlation, void *context) noexcept;

  [[nodiscard]] bool audit_operation(permissions::AuditOutcome outcome,
                                     std::uint64_t correlation,
                                     permissions::OperationId operation,
                                     permissions::GrantDecisionCode decision,
                                     std::size_t request_bytes = 0,
                                     std::size_t response_bytes = 0);
  [[nodiscard]] bool
  audit_capability(permissions::AuditEvent event,
                   permissions::AuditOutcome outcome,
                   const permissions::CapabilityKey &capability,
                   permissions::GrantDecisionCode decision);
  [[nodiscard]] bool audit_handle(permissions::AuditEvent event,
                                  permissions::AuditOutcome outcome,
                                  std::uint64_t correlation,
                                  permissions::OperationId operation,
                                  permissions::GrantDecisionCode decision);
  [[nodiscard]] TrackedRequest *find(std::uint64_t correlation);
  [[nodiscard]] TrackedRequest *
  track(std::uint64_t correlation, permissions::OperationId operation,
        const permissions::CapabilityKey &capability,
        const permissions::Scope &demand, std::uint64_t grant_epoch,
        bool authorized, permissions::GrantDecisionCode decision);
  void erase(TrackedRequest &request);
  [[nodiscard]] const permissions::GrantRecord *
  grant_for(const permissions::CapabilityKey &capability) const;

  grant::RevisionGrants revision_;
  permissions::ActivationBinding binding_;
  permissions::PermissionAuthority authority_;
  audit::AuditStore &audit_;
  providers::ProviderSet providers_;
  broker::ProviderRegistry<7> provider_registry_;
  GateRegistry gate_;
  broker::BrokerCore<kMaximumRuntimeRequests, 7> core_;
  permissions::HandleTable<kMaximumRuntimeHandles> handles_;
  std::array<std::optional<permissions::HandleId>, kMaximumRuntimeHandles>
      handle_ids_{};
  std::array<TrackedRequest, kMaximumRuntimeRequests> requests_{};
  bool failed_ = false;
  bool shutdown_ = false;
  bool shutdown_audited_ = true;
};

} // namespace omarchy::plugin_runtime::runtime
