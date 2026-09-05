#pragma once

#include "authority_store.hpp"

namespace omarchy::plugin_runtime::host_session {
class AuthorityStoreTestAccess final {
public:
  static void set_mutation_epoch(AuthorityStore &store,
                                 std::uint64_t epoch) noexcept {
    store.mutation_epoch_ = epoch;
  }
  [[nodiscard]] static AuthorityMutationResult
  replace_active(AuthorityStore &store, const policy::GrantSnapshot &snapshot) {
    return store.replace_active_for_testing(snapshot);
  }
  static void crash_at(AuthorityCrashPoint point) noexcept {
    AuthorityStore::set_crash_point_for_testing(point);
  }
  [[nodiscard]] static AuthorityRevocationResult
  revoke_active(AuthorityStore &store,
                const permissions::CapabilityKey &capability,
                std::uint64_t expected_sequence,
                AuthorityFenceObserver *observer = nullptr) {
    return store.revoke_active(capability, expected_sequence, observer);
  }
  [[nodiscard]] static AuthorityRevocationResult
  revoke_active(AuthorityStore &store,
                const definitions::CapabilityReference &definition,
                std::uint64_t expected_sequence) {
    return store.revoke_active(definition, expected_sequence);
  }
};
} // namespace omarchy::plugin_runtime::host_session
