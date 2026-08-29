#include "omarchy/plugin_runtime/providers/system_observe_provider.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <cstring>

namespace omarchy::plugin_runtime::providers {
namespace {
constexpr std::string_view kDefinition = "dc22d694f498eeb21af02a9e6d0313b20fd2a0e20db5cab64c08630999cfa84c";
constexpr std::string_view kAdapter = "59e4d0d57703e3db4f856816f298aacc2a3d80bf256b8d7e613017672c442cb3";
constexpr std::string_view kScope = "{\"datasets\":[\"compositor.window-rectangles\"]}";
}

SystemObserveProvider::SystemObserveProvider(SystemObserveProviderConfiguration configuration)
    : configuration_(std::move(configuration)) {}

definitions::DynamicAdapter SystemObserveProvider::adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("sanitized-system-observer"),
                      .implementation_digest = definitions::Digest(kAdapter),
                      .abi_version = 1},
          .dispatch = dispatch, .context = this};
}

bool SystemObserveProvider::dispatch(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written, void *opaque) noexcept {
  auto &self = *static_cast<SystemObserveProvider *>(opaque);
  written = 0;
  if (self.configuration_.epoch == 0 ||
      request.authorization.binding != self.configuration_.binding ||
      request.authorization.grant_epoch != self.configuration_.epoch ||
      request.authorization.definition.canonical_name.view() != "system.observe" ||
      request.authorization.definition.definition_generation != 1 ||
      request.authorization.definition.definition_digest.view() != kDefinition ||
      request.operation != "observe" || request.demand_scope != kScope ||
      self.configuration_.backend.window_rectangles == nullptr)
    return false;

  SanitizedWindowSnapshot snapshot;
  if (!self.configuration_.backend.window_rectangles(
          snapshot, self.configuration_.backend.context))
    return false;
  if (snapshot.width == 0 || snapshot.height == 0 ||
      snapshot.reserved_bottom > snapshot.height ||
      snapshot.window_count > snapshot.windows.size())
    return false;

  QJsonArray windows;
  for (std::size_t index = 0; index < snapshot.window_count; ++index) {
    const auto &window = snapshot.windows[index];
    if (window.opaque_id == 0 || window.width == 0 || window.height == 0 ||
        window.width > snapshot.width || window.height > snapshot.height)
      return false;
    windows.append(QJsonObject{{"id", QString::number(window.opaque_id, 16)},
                               {"x", window.x}, {"y", window.y},
                               {"width", static_cast<qint64>(window.width)},
                               {"height", static_cast<qint64>(window.height)}});
  }
  const auto bytes = QJsonDocument(QJsonObject{
      {"ok", true}, {"width", static_cast<qint64>(snapshot.width)},
      {"height", static_cast<qint64>(snapshot.height)},
      {"reservedBottom", static_cast<qint64>(snapshot.reserved_bottom)},
      {"windows", windows}}).toJson(QJsonDocument::Compact);
  if (static_cast<std::size_t>(bytes.size()) > response.size()) return false;
  std::memcpy(response.data(), bytes.constData(), static_cast<std::size_t>(bytes.size()));
  written = static_cast<std::size_t>(bytes.size());
  return true;
}

bool SystemObserveProvider::revoke(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.epoch) return false;
  configuration_.epoch = new_epoch;
  return true;
}

} // namespace omarchy::plugin_runtime::providers
