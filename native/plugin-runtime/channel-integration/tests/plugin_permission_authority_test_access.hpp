#pragma once

#ifndef OMARCHY_PLUGIN_PERMISSION_AUTHORITY_TESTING
#error "PluginPermissionAuthority test access is test-only"
#endif

#include "plugin_permission_authority.hpp"
#include "session_runtime_factory.hpp"

namespace omarchy::plugin_runtime::channel {

class PluginPermissionAuthorityTestAccess final {
public:
  static std::shared_ptr<PluginPermissionAuthority> open(
      int activation_root_fd, int revision_root_fd, int state_root_fd,
      host_session::OwnedDescriptor authority_root,
      permissions::PluginId expected_plugin, std::uint32_t trusted_uid,
      std::shared_ptr<const definitions::TrustedDefinitionRegistry> definitions,
      std::shared_ptr<const RuntimeServices> services,
      std::string fixed_record_name) {
    return PluginPermissionAuthority::open(
        activation_root_fd, revision_root_fd, state_root_fd,
        std::move(authority_root), std::move(expected_plugin), trusted_uid,
        std::move(definitions), std::move(services),
        std::move(fixed_record_name));
  }

  static std::shared_ptr<const host_session::ConsentReview>
  prepare_review(PluginPermissionAuthority &authority) {
    return authority.prepare_review();
  }

  static std::optional<host_session::AuthorityView>
  list(PluginPermissionAuthority &authority) {
    return authority.list();
  }

  static ReviewedPermissionApplyResult apply_review(
      PluginPermissionAuthority &authority,
      const host_session::ConsentReview &review,
      const host_session::ConsentConfirmation &confirmation,
      std::span<const host_session::BuiltinConsentDecision> builtin,
      std::span<const host_session::DynamicConsentDecision> dynamic) {
    return authority.apply_review(review, confirmation, builtin, dynamic);
  }
};

} // namespace omarchy::plugin_runtime::channel
