#include "omarchy/plugin_runtime/providers/github_provider.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStringList>

#include <algorithm>
#include <string>
#include <utility>

namespace omarchy::plugin_runtime::providers {
namespace {

constexpr std::string_view kReadDefinition = "9fbba69a1eefaa3ac03d950e0582b7fd81c1ec468638f04f05225a362f7bbd52";
constexpr std::string_view kWriteDefinition = "f6789af0acdcd56e4ca7266669c1619d494f6f24086502ca9b43a966cf7cffd9";
constexpr std::string_view kOpenDefinition = "8fe8b9861c976f38d1c644b67559e8ce5ba38e8f9ed8c14dfd947fbe77d85398";
constexpr std::string_view kReadAdapter = "9edc3a48f7038c3a6789c6ffae396e41cd2f42c44770214a6e09027fea8827f1";
constexpr std::string_view kWriteAdapter = "806a4071c7c679ac94d8069566b495c2afb258271e2e765f4d75c3ca0e4aae67";
constexpr std::string_view kOpenAdapter = "ac749a4136196eec99ddde7b46d75aaf6a8eaa0a687b11de09594ba3a1e4dadb";
constexpr std::string_view kReadScope = "{\"account\":\"user-selected\",\"datasets\":[\"notifications\",\"review-requests\",\"pull-requests\",\"issues\",\"actions\",\"repositories\"],\"service\":\"github.com\"}";
constexpr std::string_view kWriteScope = "{\"account\":\"same-as:remote-account.read\",\"actions\":[\"mark-notification-read\"],\"service\":\"github.com\"}";
constexpr std::string_view kOpenScope = "{\"origins\":[\"https://github.com\"],\"userGesture\":true}";

bool bounded_text(const QString &value, qsizetype maximum) {
  if (value.isEmpty() || value.size() > maximum || value.contains(QChar::Null))
    return false;
  return std::ranges::all_of(value, [](QChar character) {
    return character.unicode() >= 0x20 && character.unicode() != 0x7f;
  });
}

QJsonObject payload(const definitions::AuthorizedDynamicRequest &request) {
  return QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(request.payload.data()),
      static_cast<qsizetype>(request.payload.size()))).object();
}

} // namespace

GitHubProvider::GitHubProvider(GitHubProviderConfiguration configuration)
    : configuration_(std::move(configuration)) {}

definitions::DynamicAdapter GitHubProvider::read_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("remote-account-reader"),
                      .implementation_digest = definitions::Digest(kReadAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_read, .context = this};
}
definitions::DynamicAdapter GitHubProvider::write_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("remote-account-writer"),
                      .implementation_digest = definitions::Digest(kWriteAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_write, .context = this};
}
definitions::DynamicAdapter GitHubProvider::open_adapter() noexcept {
  return {.binding = {.adapter_class = definitions::Name("desktop-open-uri"),
                      .implementation_digest = definitions::Digest(kOpenAdapter),
                      .abi_version = 1},
          .dispatch = dispatch_open, .context = this};
}

bool GitHubProvider::authorized(
    const definitions::AuthorizedDynamicRequest &request, std::string_view name,
    std::string_view digest, std::uint64_t epoch) const noexcept {
  return epoch > 0 && request.authorization.grant_epoch == epoch &&
         request.authorization.binding == configuration_.binding &&
         request.authorization.definition.canonical_name.view() == name &&
         request.authorization.definition.definition_generation == 1 &&
         request.authorization.definition.definition_digest.view() == digest;
}

bool GitHubProvider::dispatch_read(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written,
    void *context) noexcept {
  written = 0;
  auto &self = *static_cast<GitHubProvider *>(context);
  if (!self.authorized(request, "remote-account.read", kReadDefinition,
                       self.configuration_.read_epoch) ||
      request.operation != "read" || request.demand_scope != kReadScope ||
      self.configuration_.backend.invoke == nullptr)
    return false;
  const auto object = payload(request);
  const auto datasets = object.value("datasets").toArray();
  if (object.size() != 2 || object.value("resource").toString() != "selected" ||
      datasets.size() != 6)
    return false;
  QStringList values;
  for (const auto &dataset : datasets) {
    const auto value = dataset.toString();
    if (!bounded_text(value, 32)) return false;
    values.push_back(value);
  }
  return self.configuration_.backend.invoke(
      "read", values.join(',').toStdString(), response, written,
      self.configuration_.backend.context);
}

bool GitHubProvider::dispatch_write(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written,
    void *context) noexcept {
  written = 0;
  auto &self = *static_cast<GitHubProvider *>(context);
  if (!self.authorized(request, "remote-account.write", kWriteDefinition,
                       self.configuration_.write_epoch) ||
      request.operation != "mark-read" || request.demand_scope != kWriteScope ||
      self.configuration_.backend.invoke == nullptr)
    return false;
  const auto object = payload(request);
  if (object.size() != 3 || object.value("resource").toString() != "selected" ||
      object.value("operation").toString() != "mark-notification-read")
    return false;
  QStringList handles;
  if (object.contains("id")) {
    const auto handle = object.value("id").toString();
    if (!bounded_text(handle, 64)) return false;
    handles.push_back(handle);
  } else if (object.contains("ids")) {
    const auto values = object.value("ids").toArray();
    if (values.empty() || values.size() > 25) return false;
    for (const auto &value : values) {
      const auto handle = value.toString();
      if (!bounded_text(handle, 64) || handles.contains(handle)) return false;
      handles.push_back(handle);
    }
  } else {
    return false;
  }
  return self.configuration_.backend.invoke(
      handles.size() == 1 ? "mark-read" : "mark-read-batch",
      handles.join(',').toStdString(), response, written,
      self.configuration_.backend.context);
}

bool GitHubProvider::dispatch_open(
    const definitions::AuthorizedDynamicRequest &request,
    std::span<std::byte> response, std::size_t &written,
    void *context) noexcept {
  written = 0;
  auto &self = *static_cast<GitHubProvider *>(context);
  if (!self.authorized(request, "external.open-uri.https", kOpenDefinition,
                       self.configuration_.open_epoch) ||
      request.operation != "open" || request.demand_scope != kOpenScope ||
      self.configuration_.backend.invoke == nullptr)
    return false;
  const auto object = payload(request);
  const auto handle = object.value("uriHandle").toString();
  if (object.size() != 1 || !bounded_text(handle, 64)) return false;
  return self.configuration_.backend.invoke(
      "open", handle.toStdString(), response, written,
      self.configuration_.backend.context);
}

std::size_t GitHubProvider::revoke_read(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.read_epoch) return 0;
  configuration_.read_epoch = new_epoch;
  return 0;
}
std::size_t GitHubProvider::revoke_write(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.write_epoch) return 0;
  configuration_.write_epoch = new_epoch;
  return 0;
}
std::size_t GitHubProvider::revoke_open(std::uint64_t new_epoch) noexcept {
  if (new_epoch <= configuration_.open_epoch) return 0;
  configuration_.open_epoch = new_epoch;
  return 0;
}

} // namespace omarchy::plugin_runtime::providers
