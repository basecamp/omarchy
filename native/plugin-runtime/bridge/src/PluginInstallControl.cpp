#include "PluginInstallControl.h"

#include "PluginManager.h"
#include "activation_snapshot.hpp"

#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>

#include <algorithm>
#include <array>
#include <fcntl.h>
#include <limits.h>
#include <ranges>
#include <string_view>
#include <sys/stat.h>
#include <unistd.h>

namespace omarchy::plugin_runtime::bridge {
namespace {

constexpr std::size_t kMaximumOperations = 8;
constexpr auto kPendingLifetime = std::chrono::minutes(5);
constexpr auto kCompletedLifetime = std::chrono::minutes(1);
constexpr std::uint64_t kMaximumArchiveBytes = 72U * 1024U * 1024U;

std::string opaque_id() {
  std::array<char, 40> value{};
  constexpr char hex[] = "0123456789abcdef";
  std::ranges::copy(std::string_view("install-"), value.begin());
  for (std::size_t index = 8; index < value.size(); ++index)
    value[index] = hex[QRandomGenerator::system()->generate() & 0xfU];
  return {value.data(), value.size()};
}

} // namespace

PluginInstallControl::PluginInstallControl(PluginManager &manager)
    : QObject(&manager), manager_(manager) {}

PluginInstallControl::~PluginInstallControl() = default;

QString PluginInstallControl::begin(const QString &archive_path) noexcept {
  try {
    prune();
    const auto encoded = archive_path.toUtf8();
    if (encoded.isEmpty() || encoded.size() >= PATH_MAX ||
        encoded.contains('\0') || operations_.size() >= kMaximumOperations ||
        next_serial_ == 0)
      return {};
    const int fd = ::open(encoded.constData(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW |
                                                  O_NONBLOCK);
    if (fd < 0)
      return {};
    host_session::OwnedDescriptor descriptor(fd);
    struct stat status {};
    if (::fstat(descriptor.get(), &status) != 0 || !S_ISREG(status.st_mode) ||
        status.st_size <= 0 ||
        static_cast<std::uint64_t>(status.st_size) > kMaximumArchiveBytes)
      return {};
    std::string id;
    do {
      id = opaque_id();
    } while (std::ranges::any_of(
        operations_, [&](const Operation &entry) { return entry.id == id; }));
    const auto serial = next_serial_++;
    operations_.push_back({.serial = serial,
                           .id = id,
                           .state = State::pending,
                           .touched = std::chrono::steady_clock::now(),
                           .plugin = {},
                           .revision = {},
                           .error = {},
                           .consumed = false});
    if (!manager_.beginInstall(serial, descriptor.release())) {
      operations_.pop_back();
      return {};
    }
    return QString::fromStdString(id);
  } catch (...) {
    return {};
  }
}

QString PluginInstallControl::poll(const QString &operation_id) noexcept {
  try {
    prune();
    auto *operation = find(operation_id);
    if (!operation)
      return {};
    QJsonObject response{{QStringLiteral("operationId"), operation_id}};
    if (operation->state == State::pending) {
      response.insert(QStringLiteral("state"), QStringLiteral("pending"));
    } else if (operation->state == State::failed) {
      response.insert(QStringLiteral("state"), QStringLiteral("failed"));
      response.insert(QStringLiteral("error"),
                      QString::fromStdString(operation->error));
    } else {
      response.insert(QStringLiteral("state"), QStringLiteral("succeeded"));
      response.insert(QStringLiteral("result"),
                      QJsonObject{{QStringLiteral("plugin"),
                                   QString::fromStdString(operation->plugin)}});
    }
    operation->touched = std::chrono::steady_clock::now();
    return QString::fromUtf8(
        QJsonDocument(response).toJson(QJsonDocument::Compact));
  } catch (...) {
    return {};
  }
}

QString PluginInstallControl::beginReview(
    const QString &operation_id) noexcept {
  try {
    prune();
    auto *operation = find(operation_id);
    if (!operation || operation->state != State::succeeded ||
        operation->consumed)
      return {};
    const auto review = manager_.permissions_.beginInteractiveCliReviewExact(
        operation->plugin, operation->revision);
    if (!review.isEmpty())
      operation->consumed = true;
    return review;
  } catch (...) {
    return {};
  }
}

void PluginInstallControl::complete(std::uint64_t serial, std::string plugin,
                                    std::string revision,
                                    std::string error) noexcept {
  const auto found = std::ranges::find(operations_, serial, &Operation::serial);
  if (found == operations_.end())
    return;
  found->touched = std::chrono::steady_clock::now();
  if (!error.empty()) {
    found->state = State::failed;
    found->error = std::move(error);
    return;
  }
  found->state = State::succeeded;
  found->plugin = std::move(plugin);
  found->revision = std::move(revision);
}

void PluginInstallControl::prune() noexcept {
  const auto now = std::chrono::steady_clock::now();
  std::erase_if(operations_, [&](const Operation &operation) {
    return now - operation.touched >
           (operation.state == State::pending ? kPendingLifetime
                                               : kCompletedLifetime);
  });
}

PluginInstallControl::Operation *
PluginInstallControl::find(const QString &operation_id) noexcept {
  const auto id = operation_id.toStdString();
  const auto found = std::ranges::find(operations_, id, &Operation::id);
  return found == operations_.end() ? nullptr : &*found;
}

} // namespace omarchy::plugin_runtime::bridge
