#include "PluginManager.h"
#include "PluginRuntimeController.h"

#include "SurfaceEndpointOwner.h"
#include "omarchy/plugin_runtime/Version.h"
#include "remote_surface.hpp"
#include "runtime_bootstrap.hpp"
#include "surface_host.hpp"

#include <QQmlEngine>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>
#include <QThreadPool>
#include <QTimer>

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <deque>
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
#include <functional>
#endif
#include <limits>
#include <mutex>
#include <new>
#include <optional>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <unistd.h>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::bridge {
namespace {

std::atomic<QQmlEngine *> claimed_engine = nullptr;

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
std::atomic_bool fail_next_manager_construction = false;
#endif

} // namespace

#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
void PluginManagerTestAccess::failNextConstruction() noexcept {
  fail_next_manager_construction.store(true, std::memory_order_release);
}

bool PluginManagerTestAccess::processClaimAvailable() noexcept {
  return claimed_engine.load(std::memory_order_acquire) == nullptr;
}
#endif

PluginManager::ProcessClaim::ProcessClaim(QQmlEngine *engine) noexcept
    : engine_(engine) {}

PluginManager::ProcessClaim::ProcessClaim(ProcessClaim &&other) noexcept
    : engine_(std::exchange(other.engine_, nullptr)) {}

PluginManager::ProcessClaim::~ProcessClaim() noexcept {
  if (!engine_)
    return;
  QQmlEngine *expected = engine_;
  if (!claimed_engine.compare_exchange_strong(expected, nullptr,
                                              std::memory_order_acq_rel,
                                              std::memory_order_acquire))
    std::terminate();
}

PluginManager *PluginManager::create(QQmlEngine *qml_engine,
                                     QJSEngine *js_engine) noexcept {
  if (!qml_engine || !js_engine ||
      js_engine != static_cast<QJSEngine *>(qml_engine) ||
      qml_engine->thread() != QThread::currentThread())
    return nullptr;

  QQmlEngine *expected = nullptr;
  if (!claimed_engine.compare_exchange_strong(expected, qml_engine,
                                              std::memory_order_acq_rel,
                                              std::memory_order_acquire))
    return nullptr;

  ProcessClaim claim(qml_engine);
  try {
    return new PluginManager(qml_engine, std::move(claim));
  } catch (...) {
    return nullptr;
  }
}

PluginManager::PluginManager(QObject *parent, ProcessClaim claim)
    : QObject(parent), process_claim_(std::move(claim)), surfaces_(this),
      permissions_(*this), installer_(*this) {
#ifdef OMARCHY_PLUGIN_MANAGER_TESTING
  if (fail_next_manager_construction.exchange(false, std::memory_order_acq_rel))
    throw std::bad_alloc();
#endif
  connect(&surfaces_, &SurfaceProjectionModel::surfacesChanged, this,
          &PluginManager::surfacesChanged);
  connect(&surfaces_, &SurfaceProjectionModel::openRequested, this,
          &PluginManager::openRequested);
  connect(&surfaces_, &SurfaceProjectionModel::toggleRequested, this,
          &PluginManager::toggleRequested);
  connect(&surfaces_, &SurfaceProjectionModel::dismissRequested, this,
          &PluginManager::dismissRequested);
#ifndef OMARCHY_PLUGIN_MANAGER_TESTING
  // Explicit v2 shell activation provisions fixed empty roots before the first
  // catalog scan or install. Trust roots and definitions are then immutable for
  // this singleton lifetime.
  runtime_ = detail::PluginRuntimeController::open(*this);
#endif
}

PluginManager::~PluginManager() = default;

bool PluginManager::available() const noexcept { return available_; }

QString PluginManager::runtimeVersion() const {
  const std::string_view version = plugin_runtime::build_version();
  return QString::fromLatin1(version.data(),
                             static_cast<qsizetype>(version.size()));
}

PermissionControl *PluginManager::permissions() noexcept {
  return &permissions_;
}

PluginInstallControl *PluginManager::installer() noexcept {
  return &installer_;
}

bool PluginManager::beginPermissionRead(
    std::uint64_t serial, std::string plugin, bool review,
    std::optional<plugins::permissions::Digest> expected_revision) noexcept {
  return runtime_ &&
         runtime_->beginPermissionRead(serial, std::move(plugin), review,
                                       std::move(expected_revision));
}

bool PluginManager::beginInstall(std::uint64_t serial,
                                 int archive_fd) noexcept {
  if (!runtime_) {
    ::close(archive_fd);
    return false;
  }
  return runtime_->beginInstall(serial, archive_fd);
}

void PluginManager::completeInstall(std::uint64_t serial, std::string plugin,
                                    std::string revision,
                                    std::string error) noexcept {
  installer_.complete(serial, std::move(plugin), std::move(revision),
                      std::move(error));
}

bool PluginManager::beginPermissionApply(
    std::uint64_t serial, const PermissionControl::ExactContext &context,
    std::shared_ptr<const host_session::ConsentReview> review,
    const host_session::ConsentConfirmation &confirmation,
    std::span<const host_session::BuiltinConsentDecision> builtin_decisions,
    std::span<const host_session::DynamicConsentDecision>
        dynamic_decisions) noexcept {
  return runtime_ && runtime_->beginControlledPermissionApply(
                         serial, context.plugin, context.slot_epoch,
                         context.authority, std::move(review), confirmation,
                         builtin_decisions, dynamic_decisions);
}

bool PluginManager::beginPermissionRevoke(
    std::uint64_t serial, const PermissionControl::ExactContext &context,
    const PermissionControl::Row &row) noexcept {
  return runtime_ && runtime_->beginControlledPermissionRevoke(
                         serial, context.plugin, context.slot_epoch,
                         context.authority, row.dynamic, row.builtin,
                         row.definition, context.authority_sequence);
}

void PluginManager::failPermissionControl(std::uint64_t serial,
                                          std::string error) noexcept {
  permissions_.fail(serial, std::move(error));
}

void PluginManager::completePermissionRead(
    std::uint64_t serial, std::string plugin, std::uint64_t slot_epoch,
    std::shared_ptr<channel::PluginPermissionAuthority> authority,
    std::optional<host_session::AuthorityView> view,
    std::shared_ptr<const host_session::ConsentReview> review) noexcept {
  permissions_.completeRead(serial, std::move(plugin), slot_epoch,
                            std::move(authority), std::move(view),
                            std::move(review));
}

void PluginManager::completePermissionMutation(std::uint64_t serial,
                                               bool applied,
                                               std::string error) noexcept {
  permissions_.completeMutation(serial, applied, std::move(error));
}

QAbstractItemModel *PluginManager::barSurfaces() {
  return surfaces_.barSurfaces();
}

QAbstractItemModel *PluginManager::panelSurfaces() {
  return surfaces_.panelSurfaces();
}

QAbstractItemModel *PluginManager::overlaySurfaces() {
  return surfaces_.overlaySurfaces();
}

int PluginManager::count() const noexcept { return surfaces_.count(); }

bool PluginManager::attach(const QString &surface_key,
                           QObject *surface) noexcept {
  return runtime_ && runtime_->attach(surface_key, surface);
}

bool PluginManager::configureSettingsHost(QObject *host) noexcept {
  if (!host || host->thread() != thread() || QThread::currentThread() != thread() ||
      settings_host_)
    return false;
  settings_host_ = host;
  return true;
}

bool PluginManager::configurePresentationHost(QObject *host) noexcept {
  if (!host || host->thread() != thread() ||
      QThread::currentThread() != thread() || presentation_host_)
    return false;
  presentation_host_ = host;
  return true;
}

std::optional<std::string>
PluginManager::currentSettings(std::string_view plugin) const noexcept {
  if (!settings_host_ || QThread::currentThread() != thread())
    return std::nullopt;
  QVariant returned;
  const bool invoked = QMetaObject::invokeMethod(
      settings_host_, "readSecurePluginSettings", Qt::DirectConnection,
      Q_RETURN_ARG(QVariant, returned),
      Q_ARG(QVariant, QString::fromUtf8(plugin.data(),
                                        static_cast<qsizetype>(plugin.size()))));
  if (!invoked || !returned.canConvert<QVariantMap>())
    return std::nullopt;
  const auto document = QJsonDocument::fromVariant(returned);
  if (!document.isObject())
    return std::nullopt;
  const auto bytes = document.toJson(QJsonDocument::Compact);
  return std::string(bytes.constData(), static_cast<std::size_t>(bytes.size()));
}

std::optional<std::string>
PluginManager::currentPresentation() const noexcept {
  if (!presentation_host_ || QThread::currentThread() != thread())
    return std::nullopt;
  QVariant returned;
  const bool invoked = QMetaObject::invokeMethod(
      presentation_host_, "readSecurePluginPresentation", Qt::DirectConnection,
      Q_RETURN_ARG(QVariant, returned));
  if (!invoked || !returned.canConvert<QVariantMap>())
    return std::nullopt;
  const auto document = QJsonDocument::fromVariant(returned);
  if (!document.isObject())
    return std::nullopt;
  const auto bytes = document.toJson(QJsonDocument::Compact);
  return std::string(bytes.constData(), static_cast<std::size_t>(bytes.size()));
}

bool PluginManager::persistSettings(std::string_view plugin,
                                    std::string_view canonical_entry) noexcept {
  if (!settings_host_ || QThread::currentThread() != thread())
    return false;
  const auto document = QJsonDocument::fromJson(QByteArray(
      canonical_entry.data(), static_cast<qsizetype>(canonical_entry.size())));
  if (!document.isObject())
    return false;
  QVariant returned;
  const bool invoked = QMetaObject::invokeMethod(
      settings_host_, "updateSecurePluginSettings", Qt::DirectConnection,
      Q_RETURN_ARG(QVariant, returned),
      Q_ARG(QVariant, QString::fromUtf8(plugin.data(),
                                        static_cast<qsizetype>(plugin.size()))),
      Q_ARG(QVariant, document.object().toVariantMap()));
  return invoked && returned.toBool();
}

bool PluginManager::publishIntent(host_session::AdmittedSurfaceIntent intent) {
  return surfaces_.publishIntent(std::move(intent));
}

} // namespace omarchy::plugin_runtime::bridge
