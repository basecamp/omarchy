#include "plugin_source_policy.hpp"

#include "worker_runtime.hpp"

#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <QFile>
#include <QFileInfo>
#include <QLibraryInfo>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QUrl>

#include <array>
#include <cstdint>
#include <memory>
#include <ranges>
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

bool ascii_space(char byte) {
  return byte == ' ' || byte == '\t' || byte == '\r' || byte == '\v' ||
         byte == '\f';
}

std::vector<std::string_view> qmldir_tokens(std::string_view line) {
  std::vector<std::string_view> result;
  while (!line.empty()) {
    while (!line.empty() && ascii_space(line.front()))
      line.remove_prefix(1);
    if (line.starts_with("\xef\xbb\xbf")) {
      line.remove_prefix(3);
      continue;
    }
    if (line.empty() || line.front() == '#')
      break;
    std::size_t last = 0;
    while (last < line.size() && !ascii_space(line[last]))
      ++last;
    result.push_back(line.substr(0, last));
    line.remove_prefix(last);
  }
  return result;
}

bool beneath(const std::filesystem::path &candidate,
             const std::filesystem::path &root) {
  const auto relative = candidate.lexically_relative(root);
  return !relative.empty() && !relative.is_absolute() &&
         *relative.begin() != "..";
}

} // namespace

PluginSourcePolicy::PluginSourcePolicy(std::filesystem::path source_root,
                                       std::filesystem::path qt_import_root)
    : source_root_(
          std::filesystem::absolute(std::move(source_root)).lexically_normal()),
      qt_import_root_(std::filesystem::absolute(
                          qt_import_root.empty()
                              ? std::filesystem::path(QLibraryInfo::path(
                                    QLibraryInfo::QmlImportsPath).toStdString())
                              : std::move(qt_import_root))
                          .lexically_normal()) {}

void PluginSourcePolicy::configure(QQmlEngine &engine) {
  engine.addUrlInterceptor(this);
  engine.setImportPathList(
      {QStringLiteral("qrc:/qt/qml"),
       QString::fromStdString(qt_import_root_.string()),
       QString::fromStdString(source_root_.string())});
}

RuntimeResult PluginSourcePolicy::validate_tree() const {
  return inspect_tree();
}

RuntimeResult PluginSourcePolicy::inspect_tree() const {
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
      if (iterator->path().filename() == "qmldir") {
        QFile source(QString::fromStdString(iterator->path().string()));
        if (!source.open(QIODevice::ReadOnly))
          return failure("QML module metadata cannot be opened");
        const QByteArray contents = source.readAll();
        for (const QByteArray &line : contents.split('\n')) {
          const std::string_view view(line.constData(), line.size());
          const auto fields = qmldir_tokens(view);
          if ((!fields.empty() &&
               (fields.front() == "plugin" || fields.front() == "classname" ||
                fields.front() == "linktarget" ||
                fields.front() == "prefer")) ||
              (fields.size() >= 2 && fields[0] == "optional" &&
               fields[1] == "plugin"))
            return failure("plugin-local QML modules must be pure QML");
        }
      }
    }
    iterator.increment(error);
  }
  if (error)
    return failure("plugin tree changed while validating");
  return {};
}

RuntimeResult
PluginSourcePolicy::preload_trusted_modules(QQmlEngine &engine) const {
  const auto inspected = inspect_tree();
  if (!inspected)
    return inspected;
  for (const auto &module : sandbox::trusted_qml_modules()) {
    QQmlComponent probe(&engine);
    probe.setData(QByteArray(module.probe.data(),
                             static_cast<qsizetype>(module.probe.size())),
                  QUrl(QStringLiteral(
                      "qrc:/qt/qml/Omarchy/TrustedModuleProbe.qml")));
    if (!probe.isReady())
      return failure("trusted QML module preload failed for " +
                     std::string(module.uri) + ": " +
                     probe.errorString().left(1024).toStdString());
    std::unique_ptr<QObject> object(probe.create());
    if (!object)
      return failure("trusted QML module probe could not instantiate: " +
                     std::string(module.uri));
  }
  QQmlComponent presentation_probe(&engine);
  presentation_probe.setData(
      QByteArrayLiteral("import QtQuick\n"
                        "import Omarchy.PluginPresentation 1.0\n"
                        "Item { property Component presentationType: "
                        "Component { WidgetButton {} } }"),
      QUrl(QStringLiteral(
          "qrc:/qt/qml/Omarchy/PluginPresentationProbe.qml")));
  if (!presentation_probe.isReady())
    return failure("trusted worker presentation preload failed: " +
                   presentation_probe.errorString().left(1024).toStdString());
  std::unique_ptr<QObject> presentation(presentation_probe.create());
  if (!presentation)
    return failure("trusted worker presentation probe could not instantiate");
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
    constexpr std::string_view imports = "/qt-project.org/imports/";
    const auto encoded = path.toUtf8();
    const std::string_view value(encoded.constData(), encoded.size());
    if (value.starts_with(imports) &&
        sandbox::trusted_qml_resource(value.substr(imports.size())))
      return url;
    constexpr std::string_view presentation =
        "/qt/qml/Omarchy/PluginPresentation/";
    if (value.starts_with(presentation))
      return url;
    return denied_url();
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
    if (!relative.empty() &&
        sandbox::trusted_qml_resource(relative.generic_string()))
      return url;
  }
  return denied_url();
}

QUrl PluginSourcePolicy::denied_url() {
  return QUrl(QStringLiteral("qrc:/__omarchy_plugin_resource_denied__"));
}

} // namespace omarchy::plugin_runtime::worker
