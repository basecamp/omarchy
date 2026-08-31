#include "plugin_source_policy.hpp"

#include "worker_runtime.hpp"

#include <QFile>
#include <QFileInfo>
#include <QLibraryInfo>
#include <QQmlEngine>
#include <QUrl>

#include <cstdint>
#include <system_error>
#include <utility>

namespace omarchy::plugin_runtime::worker {
namespace {

inline constexpr std::uint64_t kMaximumPluginTreeBytes =
    64ULL * 1024ULL * 1024ULL;
inline constexpr std::size_t kMaximumPluginTreeEntries = 4096;
inline constexpr std::uint64_t kMaximumResourceBytes =
    16ULL * 1024ULL * 1024ULL;

RuntimeResult failure(std::string detail) {
  return {.failure = RuntimeFailure::invalid_source_root,
          .detail = std::move(detail)};
}

bool beneath(const std::filesystem::path &candidate,
             const std::filesystem::path &root) {
  const auto relative = candidate.lexically_relative(root);
  return !relative.empty() && !relative.is_absolute() &&
         *relative.begin() != "..";
}

} // namespace

PluginSourcePolicy::PluginSourcePolicy(std::filesystem::path source_root)
    : source_root_(
          std::filesystem::absolute(std::move(source_root)).lexically_normal()),
      qt_import_root_(
          QLibraryInfo::path(QLibraryInfo::QmlImportsPath).toStdString()) {}

void PluginSourcePolicy::configure(QQmlEngine &engine) {
  engine.addUrlInterceptor(this);
  engine.setImportPathList({QString::fromStdString(source_root_.string()),
                            QLibraryInfo::path(QLibraryInfo::QmlImportsPath),
                            QStringLiteral("qrc:/qt/qml")});
}

RuntimeResult PluginSourcePolicy::validate_tree() const {
  std::error_code error;
  const auto metadata = std::filesystem::symlink_status(source_root_, error);
  if (error || !std::filesystem::is_directory(metadata) ||
      std::filesystem::is_symlink(metadata)) {
    return failure("source root must be a real directory");
  }
  std::size_t entries = 0;
  std::uint64_t total = 0;
  std::filesystem::recursive_directory_iterator iterator(
      source_root_, std::filesystem::directory_options::none, error);
  const std::filesystem::recursive_directory_iterator end;
  while (!error && iterator != end) {
    if (++entries > kMaximumPluginTreeEntries)
      return failure("plugin tree entry limit exceeded");
    const auto status = iterator->symlink_status(error);
    if (error || std::filesystem::is_symlink(status) ||
        (!std::filesystem::is_directory(status) &&
         !std::filesystem::is_regular_file(status))) {
      return failure("plugin tree contains a symlink or special file");
    }
    if (std::filesystem::is_regular_file(status)) {
      const auto size = iterator->file_size(error);
      if (error || size > kMaximumResourceBytes ||
          total > kMaximumPluginTreeBytes - size)
        return failure("plugin tree byte limit exceeded");
      total += size;
      const auto suffix = iterator->path().extension().string();
      if ((suffix == ".qml" || suffix == ".js" || suffix == ".mjs") &&
          size > kMaximumManifestBytes)
        return failure("QML or JavaScript source exceeds byte limit");
      if (suffix == ".qml") {
        QFile source(QString::fromStdString(iterator->path().string()));
        if (!source.open(QIODevice::ReadOnly))
          return failure("QML source cannot be opened");
        const auto bytes = source.readAll();
        for (QByteArray line : bytes.split('\n')) {
          line = line.trimmed();
          if (!line.startsWith("import") ||
              (line.size() > 6 && line[6] != ' ' && line[6] != '\t'))
            continue;
          line = line.sliced(6).trimmed();
          if (line.startsWith('"') || line.startsWith('\'')) {
            line = line.sliced(1).trimmed();
            if (line.startsWith('/') || line.contains("://") ||
                line.startsWith("file:") || line.startsWith("qrc:"))
              return failure("QML URL imports must stay in the plugin tree");
          }
        }
      }
    }
    iterator.increment(error);
  }
  if (error)
    return failure("plugin tree changed while validating");
  return {};
}

const std::filesystem::path &PluginSourcePolicy::root() const {
  return source_root_;
}

bool PluginSourcePolicy::valid_entry_path(std::string_view path) {
  if (path.empty() || path.size() > kMaximumEntryPathBytes ||
      path.find('\0') != std::string_view::npos || path.front() == '/' ||
      path.find('\\') != std::string_view::npos)
    return false;
  const std::filesystem::path candidate(path);
  if (candidate.extension() != ".qml" || candidate.is_absolute() ||
      candidate.lexically_normal() != candidate)
    return false;
  for (const auto &part : candidate) {
    if (part == "." || part == ".." || part.empty())
      return false;
  }
  return true;
}

QUrl PluginSourcePolicy::intercept(const QUrl &url, DataType) {
  if (url.scheme() == QStringLiteral("qrc")) {
    const auto path = url.path();
    if (path.startsWith(QStringLiteral("/qt/qml/")) ||
        path.startsWith(QStringLiteral("/qt-project.org/imports/")))
      return url;
  }
  if (!url.isLocalFile())
    return denied_url();
  const std::filesystem::path candidate(
      QFileInfo(url.toLocalFile()).absoluteFilePath().toStdString());
  const auto normalized = candidate.lexically_normal();
  if (beneath(normalized, source_root_))
    return url;
  if (beneath(normalized, qt_import_root_)) {
    const auto relative = normalized.lexically_relative(qt_import_root_);
    if (!relative.empty()) {
      const auto first = relative.begin()->string();
      if (first == "Qt" || first == "QtQml" || first == "QtQuick")
        return url;
    }
  }
  return denied_url();
}

QUrl PluginSourcePolicy::denied_url() {
  return QUrl(QStringLiteral("qrc:/__omarchy_plugin_resource_denied__"));
}

} // namespace omarchy::plugin_runtime::worker
