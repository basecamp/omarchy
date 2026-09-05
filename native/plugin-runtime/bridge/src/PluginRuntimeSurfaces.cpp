#include "PluginRuntimeController.h"

#include "remote_surface.hpp"

#include <QThread>

#include <ranges>

namespace omarchy::plugin_runtime::bridge::detail {

PluginRuntimeController::HookState::HookState(std::string plugin,
                                              std::uint64_t epoch)
    : plugin(std::move(plugin)), epoch(epoch) {}

PluginRuntimeController::Hook::Hook(std::shared_ptr<HookState> state,
                                    PluginManager &manager)
    : state(std::move(state)), manager(manager) {}

bool PluginRuntimeController::Hook::update_settings(
    const plugins::permissions::ActivationBinding &binding,
    std::string_view canonical_entry) {
  return binding.plugin.view() == state->plugin &&
         manager.persistSettings(state->plugin, canonical_entry);
}

void PluginRuntimeController::Hook::state_changed(
    host_session::SessionState session_state,
    host_session::SessionError error) {
  const auto packed = static_cast<std::uint16_t>(session_state) |
                      (static_cast<std::uint16_t>(error) << 8U);
  state->lifecycle.store(static_cast<std::uint16_t>(packed + 1U),
                         std::memory_order_release);
}

void PluginRuntimeController::Hook::render_rejected(host_session::RouteResult) {
}

bool PluginRuntimeController::Hook::accept(
    host_session::AdmittedSurfaceIntent intent) {
  try {
    if (!intent.available() || intent.binding().plugin.view() != state->plugin)
      return false;
    std::scoped_lock lock(state->intent_mutex);
    if (state->intents.size() >= HookState::maximum_pending_surface_intents)
      return false;
    state->intents.push_back(std::move(intent));
    return true;
  } catch (...) {
    return false;
  }
}

void PluginRuntimeController::withdraw(Slot &slot) noexcept {
  if (!slot.endpoint_owner)
    return;
  slot.endpoint_owner->close_all();
  try {
    static_cast<void>(
        manager_.surfaces_.withdrawSurfaces(slot.endpoint_owner->binding_));
  } catch (...) {
  }
  slot.endpoint_owner.reset();
}

void PluginRuntimeController::stateChanged(
    std::string_view plugin, std::uint64_t epoch,
    host_session::SessionState state,
    host_session::SessionError error) noexcept {
  auto *slot = exact(plugin, epoch);
  if (slot == nullptr)
    return;
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  slot->last_state = static_cast<std::uint8_t>(state);
  slot->last_error = static_cast<std::uint8_t>(error);
#endif
  if (state == host_session::SessionState::running &&
      error == host_session::SessionError::none) {
    try {
      const plugins::permissions::PluginId expected(slot->plugin);
      const auto binding =
          slot->root ? slot->root->session_binding() : std::nullopt;
      if (!binding || binding->plugin != expected) {
        if (slot->expected_binding)
          disable(*slot);
        else
          fail(*slot);
        return;
      }
      if (slot->expected_binding && *binding != *slot->expected_binding) {
        disable(*slot);
        return;
      }
      auto declarations = publicationDeclarations(*slot->root, *binding);
      const std::string exact_plugin(slot->plugin);
      if (!declarations || !publishRunning(exact_plugin, epoch, *binding,
                                           std::move(*declarations))) {
        if (auto *current = exact(exact_plugin, epoch)) {
          if (current->expected_binding)
            disable(*current);
          else
            fail(*current);
        }
        return;
      }
      if (auto *current = exact(exact_plugin, epoch)) {
        current->expected_binding.reset();
        current->retry_attempts = 0;
      }
    } catch (...) {
      if (auto *current = exact(plugin, epoch)) {
        if (current->expected_binding)
          disable(*current);
        else
          fail(*current);
      }
    }
    return;
  }
  if (state == host_session::SessionState::failed ||
      state == host_session::SessionState::stopped ||
      state == host_session::SessionState::revoked) {
    if (slot->expected_binding)
      disable(*slot);
    else
      fail(*slot);
  }
}

void PluginRuntimeController::drainSurfaceIntents(Slot &slot) noexcept {
  const auto state = slot.callback_state;
  if (!state)
    return;
  std::deque<host_session::AdmittedSurfaceIntent> pending;
  {
    std::scoped_lock lock(state->intent_mutex);
    pending.swap(state->intents);
  }
  for (auto &intent : pending) {
    try {
      if (slot.callback_state != state || slot.epoch != state->epoch ||
          slot.plugin != state->plugin || slot.phase != Phase::running)
        continue;
      std::optional<plugins::permissions::ActivationBinding> binding;
      if (slot.root && slot.endpoint_owner)
        binding = slot.root->session_binding();
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
      else if (slot.test_surface_endpoint)
        binding = slot.test_running_binding;
#endif
      if (!binding || *binding != intent.binding())
        continue;
      static_cast<void>(manager_.publishIntent(std::move(intent)));
    } catch (...) {
    }
  }
}

std::optional<std::vector<SurfaceProjectionModel::SurfaceDeclaration>>
PluginRuntimeController::publicationDeclarations(
    channel::PluginRuntimeRoot &root,
    const plugins::permissions::ActivationBinding &binding) {
  auto descriptions = root.declared_surfaces();
  if (!descriptions || descriptions->binding != binding ||
      descriptions->plugin_id != binding.plugin.view())
    return std::nullopt;
  plugins::manifest::ManifestV2 policy_source;
  policy_source.id = descriptions->plugin_id;
  policy_source.canonical_surfaces = descriptions->canonical_surfaces;
  std::vector<SurfaceProjectionModel::SurfaceDeclaration> declarations;
  declarations.reserve(descriptions->names.size());
  for (const auto &name : descriptions->names) {
    const auto policy =
        surface_host::parse_named_surface_policy(policy_source, name);
    std::optional<SurfaceProjectionModel::Role> role;
    switch (policy.role) {
    case surface_host::SurfaceRole::bar_embedded:
      role = SurfaceProjectionModel::Role::Bar;
      break;
    case surface_host::SurfaceRole::desktop_overlay:
      role = SurfaceProjectionModel::Role::Overlay;
      break;
    case surface_host::SurfaceRole::panel:
      role = SurfaceProjectionModel::Role::Panel;
      break;
    }
    std::optional<SurfaceProjectionModel::BarSection> section;
    switch (policy.default_bar_section) {
    case surface_host::BarSection::unspecified:
      section = SurfaceProjectionModel::BarSection::Unspecified;
      break;
    case surface_host::BarSection::left:
      section = SurfaceProjectionModel::BarSection::Left;
      break;
    case surface_host::BarSection::center:
      section = SurfaceProjectionModel::BarSection::Center;
      break;
    case surface_host::BarSection::right:
      section = SurfaceProjectionModel::BarSection::Right;
      break;
    }
    if (!role || !section)
      return std::nullopt;
    declarations.push_back(
        {.surface_name = policy.surface_name,
         .role = *role,
         .initially_visible = policy.initially_visible,
         .maximum_width = policy.maximum_width,
         .maximum_height = policy.maximum_height,
         .dynamic_input_regions = policy.dynamic_input_regions,
         .default_bar_section = *section});
  }
  return declarations;
}

bool PluginRuntimeController::publishRunning(
    std::string_view plugin, std::uint64_t epoch,
    const plugins::permissions::ActivationBinding &binding,
    std::vector<SurfaceProjectionModel::SurfaceDeclaration>
        declarations) noexcept {
  if (QThread::currentThread() != manager_.thread() || epoch == 0)
    return false;
  auto *slot = exact(plugin, epoch);
  if (slot == nullptr || slot->phase != Phase::starting ||
      slot->plugin != binding.plugin.view() || !slot->root || !slot->hook ||
      slot->endpoint_owner ||
      (slot->expected_binding && *slot->expected_binding != binding))
    return false;
  const auto rollback = [&]() noexcept {
    auto *current = exact(plugin, epoch);
    if (current) {
      current->phase = Phase::starting;
      if (current->endpoint_owner)
        current->endpoint_owner->close_all();
      current->endpoint_owner.reset();
    }
    try {
      static_cast<void>(manager_.surfaces_.withdrawSurfaces(binding));
    } catch (...) {
    }
  };
  try {
    const auto live_binding = slot->root->session_binding();
    if (!live_binding || *live_binding != binding)
      return false;
    if (declarations.empty()) {
      slot->phase = Phase::running;
      return true;
    }
    auto owner = std::unique_ptr<SurfaceEndpointOwner>(new SurfaceEndpointOwner(
        clock_, binding, epoch, slot->root->surface_session()));
    slot->endpoint_owner = std::move(owner);
    slot->phase = Phase::running;
    if (!manager_.surfaces_.publishSurfaces(binding, std::move(declarations),
                                            epoch)) {
      rollback();
      return false;
    }
    const auto *published = exact(plugin, epoch);
    if (published && published->phase == Phase::running &&
        published->endpoint_owner && published->root) {
      const auto exact_binding = published->root->session_binding();
      if (exact_binding && *exact_binding == binding)
        return true;
    }
    rollback();
    return false;
  } catch (...) {
    rollback();
    return false;
  }
}

bool PluginRuntimeController::attach(const QString &surface_key,
                                     QObject *surface) noexcept {
  constexpr qsizetype kMaximumPublishedSurfaceKeyCharacters = 512;
  if (QThread::currentThread() != manager_.thread() || !surface ||
      surface_key.isEmpty() ||
      surface_key.size() > kMaximumPublishedSurfaceKeyCharacters)
    return false;
  auto *remote = qobject_cast<RemotePluginSurface *>(surface);
  if (!remote)
    return false;
  try {
    auto published = manager_.surfaces_.resolve(surface_key);
    if (!published)
      return false;
    const auto plugin = published->binding_.plugin.view();
    const auto found = std::ranges::lower_bound(
        slots_, plugin, {}, [](const Slot &slot) { return slot.plugin; });
    if (found == slots_.end() || found->plugin != plugin ||
        found->phase != Phase::running ||
        found->epoch != published->publication_revision_ || !found->root ||
        !found->endpoint_owner)
      return false;
    const auto binding = found->root->session_binding();
    if (!binding || *binding != published->binding_)
      return false;
    return found->endpoint_owner->attach(*published, surface_key, *remote) ==
           SurfaceEndpointAttachResult::attached;
  } catch (...) {
    return false;
  }
}

} // namespace omarchy::plugin_runtime::bridge::detail
