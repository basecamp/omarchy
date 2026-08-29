#include "worker_runtime.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QEventPoint>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLibraryInfo>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QMouseEvent>
#include <QPointingDevice>
#include <QQmlAbstractUrlInterceptor>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickRenderControl>
#include <QQuickRenderTarget>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QTouchEvent>
#include <QUrl>
#include <QWheelEvent>

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <limits>
#include <span>
#include <system_error>
#include <unordered_set>
#include <vector>

namespace omarchy::plugin_runtime::worker {
namespace {

inline constexpr std::uint64_t kMaximumPluginTreeBytes =
    64ULL * 1024ULL * 1024ULL;
inline constexpr std::size_t kMaximumPluginTreeEntries = 4096;
inline constexpr std::uint64_t kMaximumResourceBytes =
    16ULL * 1024ULL * 1024ULL;

RuntimeResult failure(RuntimeFailure code, std::string detail) {
  return {.failure = code, .detail = std::move(detail)};
}

bool beneath(const std::filesystem::path &candidate,
             const std::filesystem::path &root) {
  const auto relative = candidate.lexically_relative(root);
  return !relative.empty() && !relative.is_absolute() &&
         *relative.begin() != "..";
}

RuntimeResult validate_source_tree(const std::filesystem::path &root) {
  std::error_code error;
  const auto metadata = std::filesystem::symlink_status(root, error);
  if (error || !std::filesystem::is_directory(metadata) ||
      std::filesystem::is_symlink(metadata)) {
    return failure(RuntimeFailure::invalid_source_root,
                   "source root must be a real directory");
  }
  std::size_t entries = 0;
  std::uint64_t total = 0;
  std::filesystem::recursive_directory_iterator iterator(
      root, std::filesystem::directory_options::none, error);
  const std::filesystem::recursive_directory_iterator end;
  while (!error && iterator != end) {
    if (++entries > kMaximumPluginTreeEntries)
      return failure(RuntimeFailure::invalid_source_root,
                     "plugin tree entry limit exceeded");
    const auto status = iterator->symlink_status(error);
    if (error || std::filesystem::is_symlink(status) ||
        (!std::filesystem::is_directory(status) &&
         !std::filesystem::is_regular_file(status))) {
      return failure(RuntimeFailure::invalid_source_root,
                     "plugin tree contains a symlink or special file");
    }
    if (std::filesystem::is_regular_file(status)) {
      const auto size = iterator->file_size(error);
      if (error || size > kMaximumResourceBytes ||
          total > kMaximumPluginTreeBytes - size)
        return failure(RuntimeFailure::invalid_source_root,
                       "plugin tree byte limit exceeded");
      total += size;
      const auto suffix = iterator->path().extension().string();
      if ((suffix == ".qml" || suffix == ".js" || suffix == ".mjs") &&
          size > kMaximumManifestBytes)
        return failure(RuntimeFailure::invalid_source_root,
                       "QML or JavaScript source exceeds byte limit");
      if (suffix == ".qml") {
        QFile source(QString::fromStdString(iterator->path().string()));
        if (!source.open(QIODevice::ReadOnly))
          return failure(RuntimeFailure::invalid_source_root,
                         "QML source cannot be opened");
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
              return failure(RuntimeFailure::invalid_source_root,
                             "QML URL imports must stay in the plugin tree");
          }
        }
      }
    }
    iterator.increment(error);
  }
  if (error)
    return failure(RuntimeFailure::invalid_source_root,
                   "plugin tree changed while validating");
  return {};
}

bool valid_runtime_api_surface(QObject &runtime_api) {
  if (runtime_api.parent() != nullptr ||
      !runtime_api.dynamicPropertyNames().empty())
    return false;
  const QMetaObject *meta = runtime_api.metaObject();
  if (meta == nullptr)
    return false;
  const int inherited_properties = QObject::staticMetaObject.propertyCount();
  const int own_properties = meta->propertyCount() - inherited_properties;
  if (own_properties != 0 && own_properties != 2)
    return false;
  if (own_properties == 2) {
    const QMetaProperty permissions = meta->property(inherited_properties);
    const QMetaProperty generation = meta->property(inherited_properties + 1);
    if (permissions.name() != QByteArrayLiteral("permissions") ||
        permissions.metaType().id() != QMetaType::QVariantMap ||
        !permissions.isReadable() || permissions.isWritable() ||
        generation.name() != QByteArrayLiteral("permissionGeneration") ||
        generation.metaType().id() != QMetaType::ULongLong ||
        !generation.isReadable() || generation.isWritable())
      return false;
  }
  std::size_t invoke = 0;
  std::size_t has_permission = 0;
  std::size_t permission_state = 0;
  std::size_t call_finished = 0;
  std::size_t permission_changed = 0;
  for (int index = QObject::staticMetaObject.methodCount();
       index < meta->methodCount(); ++index) {
    const QMetaMethod method = meta->method(index);
    if (method.access() != QMetaMethod::Public)
      return false;
    if (method.methodSignature() ==
            QByteArrayLiteral("invoke(QString,QVariantMap)") &&
        method.methodType() == QMetaMethod::Method &&
        method.returnMetaType().id() == QMetaType::QVariant &&
        method.parameterCount() == 2 &&
        method.parameterMetaType(0).id() == QMetaType::QString &&
        method.parameterMetaType(1).id() == QMetaType::QVariantMap) {
      ++invoke;
    } else if (own_properties == 2 &&
               method.methodSignature() ==
                   QByteArrayLiteral("callFinished(QObject*)") &&
               method.methodType() == QMetaMethod::Signal &&
               method.returnMetaType().id() == QMetaType::Void &&
               method.parameterCount() == 1 &&
               method.parameterMetaType(0).id() == QMetaType::QObjectStar) {
      ++call_finished;
    } else if (own_properties == 2 &&
               method.methodSignature() ==
                   QByteArrayLiteral("hasPermission(QString,QString)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::Bool &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString) {
      ++has_permission;
    } else if (own_properties == 2 &&
               method.methodSignature() ==
                   QByteArrayLiteral("permissionState(QString,QString)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::QString &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString) {
      ++permission_state;
    } else if (own_properties == 2 &&
               method.methodSignature() ==
                   QByteArrayLiteral("permissionsChanged()") &&
               method.methodType() == QMetaMethod::Signal &&
               method.returnMetaType().id() == QMetaType::Void &&
               method.parameterCount() == 0) {
      ++permission_changed;
    } else {
      return false;
    }
  }
  return invoke == 1 &&
         (own_properties == 0 ||
          (has_permission == 1 && permission_state == 1 && call_finished == 1 &&
           permission_changed == 1));
}

class ResourceInterceptor final : public QQmlAbstractUrlInterceptor {
public:
  ResourceInterceptor(std::filesystem::path plugin_root,
                      std::filesystem::path qt_root)
      : plugin_root_(std::move(plugin_root)), qt_root_(std::move(qt_root)) {}

  QUrl intercept(const QUrl &url, DataType) override {
    if (url.scheme() == QStringLiteral("qrc")) {
      const auto path = url.path();
      if (path.startsWith(QStringLiteral("/qt/qml/")) ||
          path.startsWith(QStringLiteral("/qt-project.org/imports/")))
        return url;
    }
    if (!url.isLocalFile())
      return denied();
    const std::filesystem::path candidate(
        QFileInfo(url.toLocalFile()).absoluteFilePath().toStdString());
    const auto normalized = candidate.lexically_normal();
    if (beneath(normalized, plugin_root_))
      return url;
    if (beneath(normalized, qt_root_)) {
      const auto relative = normalized.lexically_relative(qt_root_);
      if (!relative.empty()) {
        const auto first = relative.begin()->string();
        if (first == "Qt" || first == "QtQml" || first == "QtQuick")
          return url;
      }
    }
    return denied();
  }

private:
  static QUrl denied() {
    return QUrl(QStringLiteral("qrc:/__omarchy_plugin_resource_denied__"));
  }

  std::filesystem::path plugin_root_;
  std::filesystem::path qt_root_;
};

class Mapping {
public:
  Mapping() = default;
  Mapping(const Mapping &) = delete;
  Mapping &operator=(const Mapping &) = delete;
  ~Mapping() { reset(); }

  bool assign(int descriptor, std::size_t bytes) {
    reset();
    if (descriptor < 0 || bytes == 0)
      return false;
    const int access = fcntl(descriptor, F_GETFL);
    struct stat metadata{};
    if (access < 0 || (access & O_ACCMODE) != O_RDWR ||
        fstat(descriptor, &metadata) != 0 || !S_ISREG(metadata.st_mode) ||
        metadata.st_size < 0 ||
        static_cast<std::uint64_t>(metadata.st_size) != bytes) {
      close(descriptor);
      return false;
    }
    void *address =
        mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    close(descriptor);
    if (address == MAP_FAILED)
      return false;
    address_ = static_cast<std::byte *>(address);
    bytes_ = bytes;
    return true;
  }

  void reset() {
    if (address_ != nullptr)
      munmap(address_, bytes_);
    address_ = nullptr;
    bytes_ = 0;
  }

  [[nodiscard]] std::span<std::byte> bytes() { return {address_, bytes_}; }

private:
  std::byte *address_ = nullptr;
  std::size_t bytes_ = 0;
};

Qt::MouseButton mouse_button(std::uint32_t code) {
  switch (code) {
  case 1:
    return Qt::LeftButton;
  case 2:
    return Qt::RightButton;
  case 3:
    return Qt::MiddleButton;
  default:
    return static_cast<Qt::MouseButton>(Qt::ExtraButton1 << (code - 4));
  }
}

std::size_t descendants(QObject *object, std::size_t limit) {
  if (object == nullptr)
    return 0;
  std::vector<QObject *> pending{object};
  std::unordered_set<QObject *> seen;
  while (!pending.empty() && seen.size() < limit) {
    QObject *current = pending.back();
    pending.pop_back();
    if (current == nullptr || !seen.insert(current).second)
      continue;
    for (QObject *child : current->children())
      pending.push_back(child);
    if (auto *item = qobject_cast<QQuickItem *>(current)) {
      for (QQuickItem *child : item->childItems())
        pending.push_back(child);
    }
  }
  return seen.size();
}

} // namespace

struct WorkerRuntime::Impl {
  struct SurfaceInstance {
    std::string name;
    std::unique_ptr<QQmlComponent> component;
    QQuickItem *root_item = nullptr;
    std::optional<surface::SurfaceKey> bound_key;
    bool focused = false;
    Qt::MouseButtons mouse_buttons = Qt::NoButton;
    std::optional<surface::SurfaceState> state;
    std::optional<surface::InputGate> input_gate;
    std::optional<surface::FocusGate> focus_gate;
    Mapping mapping;
    QImage image;
    qreal device_pixel_ratio = 1.0;
    std::array<std::uint64_t, surface::kSlotCount> slot_sequences{};
    std::uint64_t frame_sequence = 0;
    std::uint32_t next_slot = 0;
    bool dirty = true;
  };

  explicit Impl(std::filesystem::path requested_root)
      : source_root(std::filesystem::absolute(std::move(requested_root))
                        .lexically_normal()),
        qt_root(QLibraryInfo::path(QLibraryInfo::QmlImportsPath).toStdString()),
        interceptor(source_root, qt_root), software_backend([] {
          QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
          return true;
        }()),
        render_control(), window(&render_control) {
    QImageReader::setAllocationLimit(kMaximumDecodedImageMiB);
    engine.addUrlInterceptor(&interceptor);
    engine.setImportPathList({QString::fromStdString(source_root.string()),
                              QLibraryInfo::path(QLibraryInfo::QmlImportsPath),
                              QStringLiteral("qrc:/qt/qml")});
    window.setColor(Qt::transparent);
    render_root.setParentItem(window.contentItem());
    render_root.setTransformOrigin(QQuickItem::TopLeft);
    QObject::connect(&render_control, &QQuickRenderControl::renderRequested,
                     [this] {
                       for (auto &surface : surfaces)
                         surface->dirty = true;
                     });
    QObject::connect(&render_control, &QQuickRenderControl::sceneChanged,
                     [this] {
                       for (auto &surface : surfaces)
                         surface->dirty = true;
                     });
  }

  ~Impl() {
    QObject::disconnect(&render_control, nullptr, nullptr, nullptr);
    window.setRenderTarget({});
    render_control.invalidate();
    for (auto &surface : surfaces) {
      if (surface->root_item != nullptr) {
        surface->root_item->setParentItem(nullptr);
        delete surface->root_item;
        surface->root_item = nullptr;
      }
    }
  }

  SurfaceInstance *by_key(surface::SurfaceKey key) {
    const auto found = std::ranges::find_if(surfaces, [&](const auto &entry) {
      return entry->bound_key && *entry->bound_key == key;
    });
    return found == surfaces.end() ? nullptr : found->get();
  }

  const SurfaceInstance *by_key(surface::SurfaceKey key) const {
    const auto found = std::ranges::find_if(surfaces, [&](const auto &entry) {
      return entry->bound_key && *entry->bound_key == key;
    });
    return found == surfaces.end() ? nullptr : found->get();
  }

  SurfaceInstance *by_name(std::string_view name) {
    const auto found = std::ranges::find_if(
        surfaces, [&](const auto &entry) { return entry->name == name; });
    return found == surfaces.end() ? nullptr : found->get();
  }

  void activate(SurfaceInstance &selected) {
    for (auto &entry : surfaces) {
      if (entry->root_item != nullptr && entry.get() != &selected)
        entry->root_item->setParentItem(nullptr);
    }
    if (selected.state) {
      const auto &allocation = selected.state->allocation();
      window.setGeometry(0, 0, static_cast<int>(allocation.pixel_width),
                         static_cast<int>(allocation.pixel_height));
      render_root.setSize(
          QSizeF(allocation.logical_width, allocation.logical_height));
      render_root.setScale(selected.device_pixel_ratio);
      selected.root_item->setParentItem(&render_root);
      selected.root_item->setSize(
          QSizeF(allocation.logical_width, allocation.logical_height));
      window.setRenderTarget(
          QQuickRenderTarget::fromPaintDevice(&selected.image));
    }
  }

  std::filesystem::path source_root;
  std::filesystem::path qt_root;
  ResourceInterceptor interceptor;
  QQmlEngine engine;
  [[maybe_unused]] bool software_backend;
  QQuickRenderControl render_control;
  QQuickWindow window;
  QQuickItem render_root;
  QPointingDevice mouse_device{QStringLiteral("omarchy-plugin-mouse"),
                               -1001,
                               QInputDevice::DeviceType::Mouse,
                               QPointingDevice::PointerType::Generic,
                               QInputDevice::Capability::Position |
                                   QInputDevice::Capability::Hover |
                                   QInputDevice::Capability::Scroll,
                               1,
                               16};
  QPointingDevice touch_device{QStringLiteral("omarchy-plugin-touch"),
                               -1002,
                               QInputDevice::DeviceType::TouchScreen,
                               QPointingDevice::PointerType::Finger,
                               QInputDevice::Capability::Position |
                                   QInputDevice::Capability::Area |
                                   QInputDevice::Capability::MouseEmulation,
                               static_cast<int>(surface::kMaximumTouchPoints),
                               0};
  std::vector<std::unique_ptr<SurfaceInstance>> surfaces;
  bool profile_selected = false;
  std::uint32_t maximum_pixel_dimension = 0;
  std::uint64_t maximum_frame_bytes = 0;
  std::size_t next_render_surface = 0;
  bool runtime_api_bound = false;
  std::string last_error;
};

WorkerRuntime::WorkerRuntime(std::filesystem::path source_root)
    : implementation_(std::make_unique<Impl>(std::move(source_root))) {}

WorkerRuntime::~WorkerRuntime() = default;

RuntimeResult WorkerRuntime::prepare_trusted_qt_types() {
  if (!implementation_->surfaces.empty())
    return failure(RuntimeFailure::invalid_transition,
                   "trusted Qt types must load before plugin QML");
  QQmlComponent probe(&implementation_->engine);
  probe.setData(R"(
    import QtQuick
    import QtQml as Qml
    Item {
      Qml.Timer { interval: 1000 }
    }
  )", QUrl(QStringLiteral("qrc:/qt/qml/Omarchy/TrustedTypeProbe.qml")));
  if (!probe.isReady())
    return failure(RuntimeFailure::qml_load_failed,
                   probe.errorString().left(2048).toStdString());
  std::unique_ptr<QObject> object(probe.create());
  if (!object)
    return failure(RuntimeFailure::qml_load_failed,
                   "trusted Qt type probe could not instantiate");
  return {};
}

bool safe_relative_qml_path(std::string_view path) {
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

RuntimeResult WorkerRuntime::load_manifest_entry() {
  const auto tree = validate_source_tree(implementation_->source_root);
  if (!tree)
    return tree;
  const auto manifest = implementation_->source_root / "manifest.json";
  std::error_code error;
  const auto size = std::filesystem::file_size(manifest, error);
  if (error)
    return failure(RuntimeFailure::manifest_missing, "manifest.json is absent");
  if (size > kMaximumManifestBytes)
    return failure(RuntimeFailure::manifest_oversized,
                   "manifest.json exceeds byte limit");
  QFile file(QString::fromStdString(manifest.string()));
  if (!file.open(QIODevice::ReadOnly))
    return failure(RuntimeFailure::manifest_missing,
                   "manifest.json cannot be opened");
  QJsonParseError parse_error;
  const auto document = QJsonDocument::fromJson(file.readAll(), &parse_error);
  if (parse_error.error != QJsonParseError::NoError || !document.isObject())
    return failure(RuntimeFailure::manifest_invalid,
                   "manifest.json is not a JSON object");
  const auto root = document.object();
  const auto runtime = root.value(QStringLiteral("runtime"));
  if (root.value(QStringLiteral("schemaVersion")).toInt(-1) != 2 ||
      !runtime.isObject())
    return failure(RuntimeFailure::manifest_invalid,
                   "worker requires validated manifest schema v2");
  const auto entry = runtime.toObject().value(QStringLiteral("qml"));
  if (!entry.isString())
    return failure(RuntimeFailure::manifest_invalid, "runtime.qml is required");
  return load_entry(entry.toString().toStdString());
}

RuntimeResult WorkerRuntime::bind_runtime_api(QObject &runtime_api) {
  if (implementation_->runtime_api_bound ||
      !implementation_->surfaces.empty()) {
    return failure(
        RuntimeFailure::invalid_runtime_api,
        "trusted runtime API must bind exactly once before QML load");
  }
  if (!valid_runtime_api_surface(runtime_api))
    return failure(RuntimeFailure::invalid_runtime_api,
                   "runtime API must expose only invoke(QString,QVariantMap)");
  implementation_->engine.rootContext()->setContextProperty(
      QStringLiteral("runtime"), &runtime_api);
  implementation_->runtime_api_bound = true;
  return {};
}

RuntimeResult WorkerRuntime::load_entry(std::string entry_path) {
  return load_surface_entry({}, std::move(entry_path));
}

RuntimeResult WorkerRuntime::load_surface_entry(std::string surface_name,
                                                std::string entry_path) {
  if (!safe_relative_qml_path(entry_path))
    return failure(RuntimeFailure::entry_path_invalid,
                   "QML entry path must be a normalized relative .qml file");
  const auto tree = validate_source_tree(implementation_->source_root);
  if (!tree)
    return tree;
  const auto entry = implementation_->source_root / entry_path;
  std::error_code error;
  const auto metadata = std::filesystem::symlink_status(entry, error);
  if (error || !std::filesystem::is_regular_file(metadata) ||
      std::filesystem::is_symlink(metadata))
    return failure(RuntimeFailure::entry_missing,
                   "QML entry is absent or not a regular file");
  if (implementation_->surfaces.size() >= 8 ||
      implementation_->by_name(surface_name) != nullptr)
    return failure(RuntimeFailure::invalid_transition,
                   "surface entry name is duplicate or exceeds the limit");
  auto component = std::make_unique<QQmlComponent>(
      &implementation_->engine,
      QUrl::fromLocalFile(QString::fromStdString(entry.string())),
      QQmlComponent::PreferSynchronous);
  if (!component->isReady()) {
    implementation_->last_error =
        component->errorString().left(2048).toStdString();
    if (implementation_->last_error.empty())
      implementation_->last_error =
          "QML entry did not resolve synchronously from allowed resources";
    return failure(RuntimeFailure::qml_load_failed,
                   implementation_->last_error);
  }
  QObject *created = component->create();
  auto *item = qobject_cast<QQuickItem *>(created);
  if (item == nullptr) {
    delete created;
    return failure(RuntimeFailure::root_not_item,
                   "QML entry root must be a QQuickItem, not a window");
  }
  const auto new_objects = descendants(item, kMaximumQmlObjects + 1);
  if (new_objects > kMaximumQmlObjects ||
      object_count() > kMaximumQmlObjects - new_objects) {
    delete item;
    return failure(RuntimeFailure::object_limit,
                   "QML object limit exceeded during creation");
  }
  item->setParent(&implementation_->engine);
  auto instance = std::make_unique<Impl::SurfaceInstance>();
  instance->name = std::move(surface_name);
  instance->component = std::move(component);
  instance->root_item = item;
  implementation_->surfaces.push_back(std::move(instance));
  return {};
}

RuntimeResult WorkerRuntime::bind_surface(std::string_view surface_name,
                                          surface::SurfaceKey key) {
  if (key.id == 0 || key.generation == 0 ||
      implementation_->by_key(key) != nullptr)
    return failure(RuntimeFailure::stale_surface,
                   "surface key is invalid or already bound");
  auto *instance = implementation_->by_name(surface_name);
  if (instance == nullptr || instance->bound_key)
    return failure(RuntimeFailure::invalid_transition,
                   "surface entry is absent or already bound");
  instance->bound_key = key;
  return {};
}

bool WorkerRuntime::invoke_test_function(std::string_view function) {
  constexpr std::string_view suffix = "ForTest";
  if (implementation_->surfaces.empty() || function.empty() ||
      function.size() > 96 || !function.ends_with(suffix) ||
      !std::ranges::all_of(function, [](unsigned char character) {
        return std::isalnum(character) != 0 || character == '_';
      }))
    return false;
  const QByteArray method(function.data(),
                          static_cast<qsizetype>(function.size()));
  return QMetaObject::invokeMethod(implementation_->surfaces.front()->root_item,
                                   method.constData(), Qt::DirectConnection);
}

void WorkerRuntime::request_render() {
  for (auto &surface : implementation_->surfaces)
    surface->dirty = true;
}

RuntimeResult
WorkerRuntime::select_software_profile(const surface::ProfileOffer &offer) {
  const std::array versions{offer.version};
  const auto selection = surface::select_software_profile(versions);
  if (!selection || !offer.full_frame_only || offer.shader_effects ||
      offer.particles ||
      offer.maximum_pixel_dimension > surface::kMaximumPixelDimension ||
      offer.maximum_frame_bytes > surface::kMaximumFrameBytes) {
    return failure(RuntimeFailure::profile_not_selected,
                   "host software profile is unsupported");
  }
  implementation_->profile_selected = true;
  implementation_->maximum_pixel_dimension = offer.maximum_pixel_dimension;
  implementation_->maximum_frame_bytes = offer.maximum_frame_bytes;
  return {};
}

RuntimeResult
WorkerRuntime::allocate(const surface::TrustedAllocation &allocation,
                        int mapping_descriptor) {
  if (!implementation_->profile_selected) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::profile_not_selected,
                   "profile must be selected before allocation");
  }
  if (implementation_->surfaces.empty()) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::qml_load_failed,
                   "QML must load before allocation");
  }
  if (implementation_->surfaces.size() == 1 &&
      !implementation_->surfaces.front()->bound_key)
    implementation_->surfaces.front()->bound_key = allocation.surface;
  auto *instance = implementation_->by_key(allocation.surface);
  if (instance == nullptr) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::stale_surface,
                   "allocation has no bound surface entry");
  }
  if (instance->state) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::surface_already_allocated,
                   "surface entry is already allocated");
  }
  if (allocation.pixel_width > implementation_->maximum_pixel_dimension ||
      allocation.pixel_height > implementation_->maximum_pixel_dimension ||
      allocation.frame_bytes > implementation_->maximum_frame_bytes) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::allocation_invalid,
                   "allocation exceeds negotiated software profile");
  }
  auto state = surface::SurfaceState::create(allocation);
  auto input_gate = surface::InputGate::create(allocation);
  auto focus_gate = surface::FocusGate::create(allocation);
  if (!state || !input_gate || !focus_gate) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::allocation_invalid,
                   "trusted allocation is inconsistent");
  }
  if (allocation.mapping_bytes > std::numeric_limits<std::size_t>::max() ||
      !instance->mapping.assign(
          mapping_descriptor,
          static_cast<std::size_t>(allocation.mapping_bytes)) ||
      !surface::initialize_frame_mapping(instance->mapping.bytes(),
                                         allocation))
    return failure(RuntimeFailure::mapping_invalid,
                   "shared frame mapping is not exact writable memory");
  instance->image = QImage(static_cast<int>(allocation.pixel_width),
                           static_cast<int>(allocation.pixel_height),
                           QImage::Format_RGBA8888_Premultiplied);
  if (instance->image.isNull() ||
      static_cast<std::uint32_t>(instance->image.bytesPerLine()) !=
          allocation.stride ||
      static_cast<std::uint64_t>(instance->image.sizeInBytes()) !=
          allocation.frame_bytes) {
    instance->mapping.reset();
    return failure(RuntimeFailure::allocation_invalid,
                   "QImage layout does not match trusted allocation");
  }
  instance->device_pixel_ratio =
      static_cast<qreal>(allocation.dpr_numerator) /
      static_cast<qreal>(allocation.dpr_denominator);
  if (!state->apply(surface::SurfaceTransition::activate)) {
    instance->mapping.reset();
    return failure(RuntimeFailure::invalid_transition,
                   "surface activation failed");
  }
  instance->state = std::move(state);
  instance->input_gate = std::move(input_gate);
  instance->focus_gate = std::move(focus_gate);
  instance->dirty = true;
  implementation_->activate(*instance);
  return {};
}

RuntimeResult WorkerRuntime::suspend(surface::SurfaceKey key) {
  auto *instance = implementation_->by_key(key);
  if (instance == nullptr || !instance->state)
    return failure(RuntimeFailure::stale_surface, "stale surface suspend");
  if (!instance->state->apply(surface::SurfaceTransition::suspend))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot suspend in current phase");
  instance->focused = false;
  instance->mouse_buttons = Qt::NoButton;
  return {};
}

RuntimeResult WorkerRuntime::resume(surface::SurfaceKey key) {
  auto *instance = implementation_->by_key(key);
  if (instance == nullptr || !instance->state)
    return failure(RuntimeFailure::stale_surface, "stale surface resume");
  if (!instance->state->apply(surface::SurfaceTransition::resume))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot resume in current phase");
  instance->dirty = true;
  return {};
}

RuntimeResult WorkerRuntime::release(surface::SurfaceKey key) {
  auto *instance = implementation_->by_key(key);
  if (instance == nullptr || !instance->state)
    return failure(RuntimeFailure::stale_surface, "stale surface release");
  if (!instance->state->apply(
          surface::SurfaceTransition::begin_destroy) ||
      !instance->state->apply(
          surface::SurfaceTransition::finish_destroy))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot release in current phase");
  instance->root_item->setParentItem(nullptr);
  implementation_->window.setRenderTarget({});
  instance->mapping.reset();
  instance->image = {};
  instance->device_pixel_ratio = 1.0;
  instance->input_gate.reset();
  instance->focus_gate.reset();
  instance->state.reset();
  instance->focused = false;
  instance->mouse_buttons = Qt::NoButton;
  instance->bound_key.reset();
  return {};
}

RuntimeResult WorkerRuntime::focus(const surface::FocusEvent &event) {
  auto *instance = implementation_->by_key(event.surface);
  if (instance == nullptr || !instance->state || !instance->focus_gate)
    return failure(RuntimeFailure::invalid_input, "surface is not allocated");
  const bool active =
      instance->state->phase() == surface::SurfacePhase::active;
  if (instance->focus_gate->accept(event, active) !=
      surface::InputValidation::accepted)
    return failure(RuntimeFailure::invalid_input,
                   "focus event failed the monotonic surface gate");
  instance->focused = event.focused;
  implementation_->activate(*instance);
  if (event.focused) {
    for (auto &other : implementation_->surfaces) {
      if (other.get() != instance) {
        other->focused = false;
        other->mouse_buttons = Qt::NoButton;
        other->root_item->setFocus(false, Qt::OtherFocusReason);
      }
    }
    instance->root_item->forceActiveFocus(Qt::OtherFocusReason);
  }
  else {
    instance->root_item->setFocus(false, Qt::OtherFocusReason);
    instance->mouse_buttons = Qt::NoButton;
  }
  return {};
}

RuntimeResult WorkerRuntime::input(const surface::InputEvent &event) {
  auto *instance = implementation_->by_key(event.surface);
  if (instance == nullptr || !instance->state || !instance->input_gate)
    return failure(RuntimeFailure::invalid_input, "surface is not allocated");
  const bool active =
      instance->state->phase() == surface::SurfacePhase::active;
  if (instance->input_gate->accept(event, active, instance->focused) !=
      surface::InputValidation::accepted)
    return failure(RuntimeFailure::invalid_input,
                   "input failed the monotonic surface/focus gate");
  implementation_->activate(*instance);
  const auto device_pixel_ratio = instance->device_pixel_ratio;
  const QPointF point(
      static_cast<qreal>(event.x_q16) / 65536.0 * device_pixel_ratio,
      static_cast<qreal>(event.y_q16) / 65536.0 * device_pixel_ratio);
  if (event.kind == surface::InputKind::pointer_motion) {
    QMouseEvent translated(QEvent::MouseMove, point, point, point, Qt::NoButton,
                           instance->mouse_buttons, Qt::NoModifier,
                           &implementation_->mouse_device);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  } else if (event.kind == surface::InputKind::pointer_button) {
    const auto button = mouse_button(event.code);
    const bool pressed = event.state == static_cast<std::uint32_t>(
                                            surface::ButtonState::pressed);
    const auto buttons = pressed ? instance->mouse_buttons | button
                                 : instance->mouse_buttons & ~button;
    QMouseEvent translated(pressed ? QEvent::MouseButtonPress
                                   : QEvent::MouseButtonRelease,
                           point, point, point, button, buttons, Qt::NoModifier,
                           &implementation_->mouse_device);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
    instance->mouse_buttons = buttons;
  } else if (event.kind == surface::InputKind::scroll) {
    const QPoint pixel_delta(qRound(static_cast<qreal>(event.delta_x_q16) /
                                    65536.0 * device_pixel_ratio),
                             qRound(static_cast<qreal>(event.delta_y_q16) /
                                    65536.0 * device_pixel_ratio));
    QWheelEvent translated(point, point, pixel_delta, {}, Qt::NoButton,
                           Qt::NoModifier, Qt::ScrollUpdate, false,
                           Qt::MouseEventNotSynthesized,
                           &implementation_->mouse_device);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  } else if (event.kind == surface::InputKind::key) {
    const bool pressed = event.state == static_cast<std::uint32_t>(
                                            surface::ButtonState::pressed);
    QKeyEvent translated(pressed ? QEvent::KeyPress : QEvent::KeyRelease, 0,
                         Qt::NoModifier, event.code, 0, 0);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  } else {
    const auto state = event.state == 1   ? QEventPoint::State::Pressed
                       : event.state == 2 ? QEventPoint::State::Updated
                                          : QEventPoint::State::Released;
    const auto type = event.state == 1   ? QEvent::TouchBegin
                      : event.state == 2 ? QEvent::TouchUpdate
                                         : QEvent::TouchEnd;
    QTouchEvent translated(
        type, &implementation_->touch_device, Qt::NoModifier,
        {QEventPoint(static_cast<int>(event.code), state, point, point)});
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  }
  instance->dirty = true;
  return {};
}

std::optional<PublishedFrame> WorkerRuntime::render() {
  if (!active() || implementation_->surfaces.empty())
    return std::nullopt;
  Impl::SurfaceInstance *instance = nullptr;
  for (std::size_t offset = 0; offset < implementation_->surfaces.size();
       ++offset) {
    const auto index =
        (implementation_->next_render_surface + offset) %
        implementation_->surfaces.size();
    auto &candidate = implementation_->surfaces[index];
    if (candidate->dirty && candidate->state &&
        candidate->state->phase() == surface::SurfacePhase::active) {
      instance = candidate.get();
      implementation_->next_render_surface =
          (index + 1) % implementation_->surfaces.size();
      break;
    }
  }
  if (instance == nullptr)
    return std::nullopt;
  instance->dirty = false;
  const auto count = object_count();
  if (count > kMaximumQmlObjects) {
    implementation_->last_error = "QML object limit exceeded before render";
    return std::nullopt;
  }
  implementation_->activate(*instance);
  instance->image.fill(Qt::transparent);
  implementation_->render_control.polishItems();
  implementation_->render_control.sync();
  implementation_->render_control.render();
  const auto &allocation = instance->state->allocation();
  const auto slot = instance->next_slot;
  instance->next_slot = (slot + 1) % surface::kSlotCount;
  auto &slot_sequence = instance->slot_sequences[slot];
  if (slot_sequence > std::numeric_limits<std::uint64_t>::max() - 2 ||
      instance->frame_sequence ==
          std::numeric_limits<std::uint64_t>::max()) {
    implementation_->last_error = "frame sequence exhausted";
    return std::nullopt;
  }
  slot_sequence += 2;
  ++instance->frame_sequence;
  const auto *pixel_bytes =
      reinterpret_cast<const std::byte *>(instance->image.constBits());
  const std::span<const std::byte> pixels(
      pixel_bytes,
      static_cast<std::size_t>(instance->image.sizeInBytes()));
  if (surface::publish_frame(instance->mapping.bytes(), allocation, slot,
                             slot_sequence, instance->frame_sequence,
                             pixels) != surface::PublishResult::published) {
    implementation_->last_error = "shared frame publication failed";
    return std::nullopt;
  }
  return PublishedFrame{
      .ready = {.surface = allocation.surface,
                .slot = slot,
                .slot_sequence = slot_sequence,
                .frame_sequence = instance->frame_sequence},
      .rendered_objects = count};
}

std::optional<surface::InputRegionUpdate>
WorkerRuntime::input_region_update(surface::SurfaceKey key,
                                   std::uint64_t generation) const {
  const auto *instance = implementation_->by_key(key);
  if (instance == nullptr || !instance->state ||
      instance->state->phase() != surface::SurfacePhase::active ||
      instance->root_item == nullptr || generation == 0)
    return std::nullopt;
  const auto property = instance->root_item->property("inputRegions");
  if (!property.isValid()) return std::nullopt;
  const auto values = property.toList();
  if (values.size() > static_cast<qsizetype>(surface::kMaximumTransportedInputRegions))
    return std::nullopt;
  surface::InputRegionUpdate update{.surface = instance->state->allocation().surface,
                                    .generation = generation,
                                    .count = static_cast<std::uint32_t>(values.size())};
  for (qsizetype index = 0; index < values.size(); ++index) {
    const auto map = values[index].toMap();
    if (map.size() != 4) return std::nullopt;
    bool x_ok = false, y_ok = false, width_ok = false, height_ok = false;
    const auto x = map.value(QStringLiteral("x")).toInt(&x_ok);
    const auto y = map.value(QStringLiteral("y")).toInt(&y_ok);
    const auto width = map.value(QStringLiteral("width")).toUInt(&width_ok);
    const auto height = map.value(QStringLiteral("height")).toUInt(&height_ok);
    if (!x_ok || !y_ok || !width_ok || !height_ok || width == 0 || height == 0)
      return std::nullopt;
    update.regions[static_cast<std::size_t>(index)] = {
        .x = x, .y = y, .width = width, .height = height};
  }
  return update;
}

bool WorkerRuntime::loaded() const {
  return !implementation_->surfaces.empty();
}

bool WorkerRuntime::allocated() const {
  return std::ranges::any_of(implementation_->surfaces,
                             [](const auto &entry) {
                               return entry->state.has_value();
                             });
}

bool WorkerRuntime::active() const {
  return std::ranges::any_of(implementation_->surfaces,
                             [](const auto &entry) {
                               return entry->state &&
                                      entry->state->phase() ==
                                          surface::SurfacePhase::active;
                             });
}

bool WorkerRuntime::focused() const {
  return std::ranges::any_of(implementation_->surfaces,
                             [](const auto &entry) {
                               return entry->focused;
                             });
}

bool WorkerRuntime::render_requested() const {
  return std::ranges::any_of(implementation_->surfaces,
                             [](const auto &entry) {
                               return entry->dirty;
                             });
}

std::size_t WorkerRuntime::object_count() const {
  std::size_t total = 0;
  for (const auto &entry : implementation_->surfaces) {
    const auto count = descendants(entry->root_item, kMaximumQmlObjects + 1);
    if (count > kMaximumQmlObjects - std::min(total, kMaximumQmlObjects))
      return kMaximumQmlObjects + 1;
    total += count;
  }
  return total;
}

const std::string &WorkerRuntime::last_error() const {
  return implementation_->last_error;
}

} // namespace omarchy::plugin_runtime::worker
