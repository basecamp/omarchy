#include "worker_runtime.hpp"

#include "plugin_source_policy.hpp"
#include "qt_touch_injector.hpp"

#include "omarchy/plugin/wire/surface_name.hpp"

#include <QCoreApplication>
#include <QEventPoint>
#include <QFile>
#include <QImage>
#include <QImageReader>
#include <QInputMethodEvent>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QMetaMethod>
#include <QMetaProperty>
#include <QMouseEvent>
#include <QPointingDevice>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickRenderControl>
#include <QQuickRenderTarget>
#include <QQuickWindow>
#include <QSGRendererInterface>
#include <QUrl>
#include <QWheelEvent>

#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <limits>
#include <span>
#include <system_error>
#include <unordered_set>
#include <vector>

namespace omarchy::plugin_runtime::worker {
namespace {

RuntimeResult failure(RuntimeFailure code, std::string detail) {
  return {.failure = code, .detail = std::move(detail)};
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
  if (own_properties != 0 && own_properties != 4)
    return false;
  if (own_properties == 4) {
    const QMetaProperty permissions = meta->property(inherited_properties);
    const QMetaProperty settings = meta->property(inherited_properties + 1);
    const QMetaProperty generation = meta->property(inherited_properties + 2);
    const QMetaProperty ready = meta->property(inherited_properties + 3);
    if (permissions.name() != QByteArrayLiteral("permissions") ||
        permissions.metaType().id() != QMetaType::QVariantMap ||
        !permissions.isReadable() || permissions.isWritable() ||
        !permissions.isConstant() || permissions.hasNotifySignal() ||
        settings.name() != QByteArrayLiteral("settings") ||
        settings.metaType().id() != QMetaType::QVariantMap ||
        !settings.isReadable() || settings.isWritable() ||
        settings.isConstant() || !settings.hasNotifySignal() ||
        settings.notifySignal().methodSignature() !=
            QByteArrayLiteral("settingsChanged()") ||
        generation.name() != QByteArrayLiteral("permissionGeneration") ||
        generation.metaType().id() != QMetaType::ULongLong ||
        !generation.isReadable() || generation.isWritable() ||
        !generation.isConstant() || generation.hasNotifySignal() ||
        ready.name() != QByteArrayLiteral("brokerReady") ||
        ready.metaType().id() != QMetaType::Bool || !ready.isReadable() ||
        ready.isWritable() || ready.isConstant() || !ready.hasNotifySignal() ||
        ready.notifySignal().methodSignature() !=
            QByteArrayLiteral("brokerReadyChanged()"))
      return false;
  }
  std::size_t invoke = 0;
  std::size_t has_permission = 0;
  std::size_t permission_state = 0;
  std::size_t call_finished = 0;
  std::size_t read_packaged_text = 0;
  std::size_t request_surface_intent = 0;
  std::size_t request_surface_intent_data = 0;
  std::size_t update_settings = 0;
  std::size_t broker_ready_changed = 0;
  std::size_t settings_changed = 0;
  for (int index = QObject::staticMetaObject.methodCount();
       index < meta->methodCount(); ++index) {
    const QMetaMethod method = meta->method(index);
    if (method.access() != QMetaMethod::Public)
      return false;
    if (method.methodSignature() ==
            QByteArrayLiteral("invoke(QString,QString,QVariantMap)") &&
        method.methodType() == QMetaMethod::Method &&
        method.returnMetaType().id() == QMetaType::QVariant &&
        method.parameterCount() == 3 &&
        method.parameterMetaType(0).id() == QMetaType::QString &&
        method.parameterMetaType(1).id() == QMetaType::QString &&
        method.parameterMetaType(2).id() == QMetaType::QVariantMap) {
      ++invoke;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("requestSurfaceIntent(QString,QString)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::Bool &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString) {
      ++request_surface_intent;
    } else if (own_properties == 4 &&
               method.methodSignature() == QByteArrayLiteral(
                   "requestSurfaceIntent(QString,QString,QVariantMap)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::Bool &&
               method.parameterCount() == 3 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString &&
               method.parameterMetaType(2).id() == QMetaType::QVariantMap) {
      ++request_surface_intent_data;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("readPackagedText(QString,int)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::QString &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::Int) {
      ++read_packaged_text;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("callFinished(QObject*)") &&
               method.methodType() == QMetaMethod::Signal &&
               method.returnMetaType().id() == QMetaType::Void &&
               method.parameterCount() == 1 &&
               method.parameterMetaType(0).id() == QMetaType::QObjectStar) {
      ++call_finished;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("hasPermission(QString,QString)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::Bool &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString) {
      ++has_permission;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("permissionState(QString,QString)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::QString &&
               method.parameterCount() == 2 &&
               method.parameterMetaType(0).id() == QMetaType::QString &&
               method.parameterMetaType(1).id() == QMetaType::QString) {
      ++permission_state;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("updateSettings(QVariantMap)") &&
               method.methodType() == QMetaMethod::Method &&
               method.returnMetaType().id() == QMetaType::Bool &&
               method.parameterCount() == 1 &&
               method.parameterMetaType(0).id() == QMetaType::QVariantMap) {
      ++update_settings;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("brokerReadyChanged()") &&
               method.methodType() == QMetaMethod::Signal &&
               method.returnMetaType().id() == QMetaType::Void &&
               method.parameterCount() == 0) {
      ++broker_ready_changed;
    } else if (own_properties == 4 &&
               method.methodSignature() ==
                   QByteArrayLiteral("settingsChanged()") &&
               method.methodType() == QMetaMethod::Signal &&
               method.returnMetaType().id() == QMetaType::Void &&
               method.parameterCount() == 0) {
      ++settings_changed;
    } else {
      return false;
    }
  }
  return invoke == 1 &&
         (own_properties == 0 ||
          (has_permission == 1 && permission_state == 1 &&
           read_packaged_text == 1 && call_finished == 1 &&
           request_surface_intent == 1 && request_surface_intent_data == 1 &&
           update_settings == 1 &&
           broker_ready_changed == 1 && settings_changed == 1));
}

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

QPointF input_position(surface::InputPoint position, qreal device_pixel_ratio) {
  return {static_cast<qreal>(position.x_q16) / 65536.0 * device_pixel_ratio,
          static_cast<qreal>(position.y_q16) / 65536.0 * device_pixel_ratio};
}

Qt::ScrollPhase scroll_phase(surface::WheelPhase phase) {
  switch (phase) {
  case surface::WheelPhase::discrete:
    return Qt::NoScrollPhase;
  case surface::WheelPhase::begin:
    return Qt::ScrollBegin;
  case surface::WheelPhase::update:
    return Qt::ScrollUpdate;
  case surface::WheelPhase::momentum:
    return Qt::ScrollMomentum;
  case surface::WheelPhase::end:
    return Qt::ScrollEnd;
  }
  return Qt::NoScrollPhase;
}

bool item_belongs_to(QQuickItem *root, QQuickItem *candidate) {
  return root != nullptr && candidate != nullptr &&
         (candidate == root || root->isAncestorOf(candidate));
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
    // Pointer grabs, touch delivery, and active focus belong to a QQuickWindow.
    // Keep each surface in one scene for its full allocation lifetime so
    // rendering a sibling cannot interrupt an in-flight interaction.
    SurfaceInstance() : render_control(), window(&render_control) {
      window.setColor(Qt::transparent);
      render_root.setParentItem(window.contentItem());
      render_root.setTransformOrigin(QQuickItem::TopLeft);
      QObject::connect(&render_control,
                       &QQuickRenderControl::renderRequested,
                       [this] { dirty = true; });
      QObject::connect(&render_control, &QQuickRenderControl::sceneChanged,
                       [this] { dirty = true; });
    }

    std::string name;
    std::unique_ptr<QQmlComponent> component;
    QQuickItem *root_item = nullptr;
    std::optional<surface::SurfaceKey> bound_key;
    std::optional<surface::SurfaceState> state;
    Mapping mapping;
    QImage image;
    qreal device_pixel_ratio = 1.0;
    std::array<std::uint64_t, surface::kSlotCount> slot_sequences{};
    std::uint64_t frame_sequence = 0;
    std::uint32_t next_slot = 0;
    bool dirty = true;
    QQuickRenderControl render_control;
    QQuickWindow window;
    QQuickItem render_root;
  };

  explicit Impl(std::filesystem::path requested_root,
                std::filesystem::path qt_import_root)
      : source_policy(std::move(requested_root), std::move(qt_import_root)),
        software_backend([] {
          QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
          return true;
        }()) {
    QImageReader::setAllocationLimit(kMaximumDecodedImageMiB);
    source_policy.configure(engine);
  }

  ~Impl() {
    for (auto &surface : surfaces) {
      QObject::disconnect(&surface->render_control, nullptr, nullptr, nullptr);
      surface->window.setRenderTarget({});
      surface->render_control.invalidate();
      if (surface->root_item != nullptr) {
        surface->root_item->setParentItem(nullptr);
        delete surface->root_item;
        surface->root_item = nullptr;
      }
    }
    if (headless_root_item != nullptr) {
      delete headless_root_item;
      headless_root_item = nullptr;
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

  void configure_scene(SurfaceInstance &instance) {
    if (!instance.state)
      return;
    const auto &allocation = instance.state->allocation();
    instance.window.setGeometry(0, 0,
                                static_cast<int>(allocation.pixel_width),
                                static_cast<int>(allocation.pixel_height));
    instance.render_root.setSize(
        QSizeF(allocation.logical_width, allocation.logical_height));
    instance.render_root.setScale(instance.device_pixel_ratio);
    instance.root_item->setParentItem(&instance.render_root);
    instance.root_item->setSize(
        QSizeF(allocation.logical_width, allocation.logical_height));
    instance.window.setRenderTarget(
        QQuickRenderTarget::fromPaintDevice(&instance.image));
  }

  void cancel_input(SurfaceInstance &instance, bool touch_was_active) {
    if (touch_was_active)
      touch_injector.cancel(instance.window);
    auto *mouse_grabber = instance.window.mouseGrabberItem();
    if (item_belongs_to(instance.root_item, mouse_grabber))
      mouse_grabber->ungrabMouse();
    std::vector<QQuickItem *> pending{instance.root_item};
    std::unordered_set<QQuickItem *> seen;
    while (!pending.empty() && seen.size() < kMaximumQmlObjects) {
      QQuickItem *item = pending.back();
      pending.pop_back();
      if (item == nullptr || !seen.insert(item).second)
        continue;
      if (item != mouse_grabber)
        item->ungrabMouse();
      item->ungrabTouchPoints();
      item->setFocus(false, Qt::OtherFocusReason);
      for (QQuickItem *child : item->childItems())
        pending.push_back(child);
    }
    if (instance.bound_key)
      input_mirror.release(*instance.bound_key);
  }

  PluginSourcePolicy source_policy;
  QQmlEngine engine;
  [[maybe_unused]] bool software_backend;
  QtTouchInjector touch_injector;
  surface::InputMirror input_mirror;
  std::vector<std::unique_ptr<SurfaceInstance>> surfaces;
  std::unique_ptr<QQmlComponent> headless_component;
  QQuickItem *headless_root_item = nullptr;
  bool profile_selected = false;
  std::uint32_t maximum_pixel_dimension = 0;
  std::uint64_t maximum_frame_bytes = 0;
  std::size_t next_render_surface = 0;
  bool runtime_api_bound = false;
  std::string last_error;
};

WorkerRuntime::WorkerRuntime(std::filesystem::path source_root,
                             std::filesystem::path qt_import_root)
    : implementation_(std::make_unique<Impl>(std::move(source_root),
                                             std::move(qt_import_root))) {}

WorkerRuntime::~WorkerRuntime() = default;

std::string WorkerRuntime::root_object_name() const {
  const QQuickItem *root = implementation_->headless_root_item;
  if (root == nullptr && !implementation_->surfaces.empty())
    root = implementation_->surfaces.front()->root_item;
  return root == nullptr ? std::string{} : root->objectName().toStdString();
}

RuntimeResult WorkerRuntime::prepare_trusted_qt_types() {
  if (loaded())
    return failure(RuntimeFailure::invalid_transition,
                   "trusted Qt types must load before plugin QML");
  return implementation_->source_policy.preload_trusted_modules(
      implementation_->engine);
}

bool safe_relative_qml_path(std::string_view path) {
  return PluginSourcePolicy::valid_entry_path(path);
}

RuntimeResult WorkerRuntime::load_manifest_entry() {
  const auto tree = implementation_->source_policy.validate_tree();
  if (!tree)
    return tree;
  const auto manifest = implementation_->source_policy.root() / "manifest.json";
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
  const auto surfaces = root.value(QStringLiteral("surfaces"));
  if (!surfaces.isObject() || surfaces.toObject().size() > 1)
    return failure(RuntimeFailure::manifest_invalid,
                   "single-entry runtime permits at most one surface");
  if (surfaces.toObject().isEmpty())
    return load_entry(entry.toString().toStdString());
  return load_surface_entry(surfaces.toObject().begin().key().toStdString(),
                            entry.toString().toStdString());
}

RuntimeResult WorkerRuntime::bind_runtime_api(QObject &runtime_api) {
  if (implementation_->runtime_api_bound || loaded()) {
    return failure(
        RuntimeFailure::invalid_runtime_api,
        "trusted runtime API must bind exactly once before QML load");
  }
  if (!valid_runtime_api_surface(runtime_api))
    return failure(RuntimeFailure::invalid_runtime_api,
                   "runtime API must expose only "
                   "the exact trusted broker, permission, settings, and "
                   "surface API");
  implementation_->engine.rootContext()->setContextProperty(
      QStringLiteral("runtime"), &runtime_api);
  implementation_->runtime_api_bound = true;
  return {};
}

RuntimeResult WorkerRuntime::load_entry(std::string entry_path) {
  if (loaded())
    return failure(RuntimeFailure::invalid_transition,
                   "headless entry must be the only QML entry");
  std::unique_ptr<QQmlComponent> component;
  QQuickItem *root_item = nullptr;
  const auto loaded =
      instantiate_entry(std::move(entry_path), component, root_item);
  if (!loaded)
    return loaded;
  implementation_->headless_component = std::move(component);
  implementation_->headless_root_item = root_item;
  return {};
}

RuntimeResult WorkerRuntime::instantiate_entry(
    std::string entry_path, std::unique_ptr<QQmlComponent> &component,
    QQuickItem *&root_item) {
  if (!safe_relative_qml_path(entry_path))
    return failure(RuntimeFailure::entry_path_invalid,
                   "QML entry path must be a normalized relative .qml file");
  const auto tree = implementation_->source_policy.validate_tree();
  if (!tree)
    return tree;
  const auto entry = implementation_->source_policy.root() / entry_path;
  std::error_code error;
  const auto metadata = std::filesystem::symlink_status(entry, error);
  if (error || !std::filesystem::is_regular_file(metadata) ||
      std::filesystem::is_symlink(metadata))
    return failure(RuntimeFailure::entry_missing,
                   "QML entry is absent or not a regular file");
  component = std::make_unique<QQmlComponent>(
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
  root_item = item;
  return {};
}

RuntimeResult WorkerRuntime::load_surface_entry(std::string surface_name,
                                                std::string entry_path) {
  if (implementation_->headless_root_item != nullptr ||
      implementation_->surfaces.size() >=
          omarchy::plugin::wire::kMaximumPluginSurfaces ||
      implementation_->by_name(surface_name) != nullptr)
    return failure(RuntimeFailure::invalid_transition,
                   "surface entry name is duplicate or exceeds the limit");
  std::unique_ptr<QQmlComponent> component;
  QQuickItem *root_item = nullptr;
  const auto loaded =
      instantiate_entry(std::move(entry_path), component, root_item);
  if (!loaded)
    return loaded;
  auto instance = std::make_unique<Impl::SurfaceInstance>();
  instance->name = std::move(surface_name);
  instance->component = std::move(component);
  instance->root_item = root_item;
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

std::optional<surface::SurfaceKey>
WorkerRuntime::surface_key(std::string_view surface_name) const {
  const auto *instance = implementation_->by_name(surface_name);
  if (instance == nullptr)
    return std::nullopt;
  return instance->bound_key;
}

bool WorkerRuntime::can_deliver_surface_intent(
    std::string_view surface_name) const {
  const auto *instance = implementation_->by_name(surface_name);
  return instance != nullptr && instance->bound_key &&
         instance->root_item != nullptr &&
         instance->root_item->metaObject()->indexOfMethod(
             "receiveSurfaceIntent(QVariant)") >= 0;
}

bool WorkerRuntime::deliver_surface_intent(std::string_view surface_name,
                                           const QVariantMap &data) {
  auto *instance = implementation_->by_name(surface_name);
  if (instance == nullptr || !instance->bound_key ||
      instance->root_item == nullptr)
    return false;
  const bool delivered = QMetaObject::invokeMethod(
      instance->root_item, "receiveSurfaceIntent", Qt::DirectConnection,
      Q_ARG(QVariant, QVariant(data)));
  if (delivered)
    instance->dirty = true;
  return delivered;
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
    if (!loaded())
      return failure(RuntimeFailure::qml_load_failed,
                     "QML must load before allocation");
    return failure(RuntimeFailure::stale_surface,
                   "headless QML has no surface allocation authority");
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
  if (!state) {
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
  instance->dirty = true;
  implementation_->configure_scene(*instance);
  return {};
}

RuntimeResult WorkerRuntime::suspend(surface::SurfaceKey key) {
  auto *instance = implementation_->by_key(key);
  if (instance == nullptr || !instance->state)
    return failure(RuntimeFailure::stale_surface, "stale surface suspend");
  if (instance->state->phase() != surface::SurfacePhase::active)
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot suspend in current phase");
  const bool touch_was_active =
      implementation_->input_mirror.touch_active(key);
  implementation_->cancel_input(*instance, touch_was_active);
  if (!instance->state->apply(surface::SurfaceTransition::suspend))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot suspend in current phase");
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
  const bool touch_was_active =
      implementation_->input_mirror.touch_active(key);
  implementation_->cancel_input(*instance, touch_was_active);
  if (!instance->state->apply(
          surface::SurfaceTransition::begin_destroy) ||
      !instance->state->apply(
          surface::SurfaceTransition::finish_destroy))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot release in current phase");
  instance->root_item->setParentItem(nullptr);
  instance->window.setRenderTarget({});
  instance->mapping.reset();
  instance->image = {};
  instance->device_pixel_ratio = 1.0;
  instance->state.reset();
  // The authenticated name-to-key binding is valid for the worker generation;
  // only the allocation belongs to this attachment lifetime.
  return {};
}

RuntimeResult WorkerRuntime::input(const surface::InputEvent &event) {
  auto *instance = implementation_->by_key(event.surface);
  if (instance == nullptr || !instance->state)
    return failure(RuntimeFailure::invalid_input, "surface is not allocated");
  const bool active =
      instance->state->phase() == surface::SurfacePhase::active;
  const bool touch_was_active =
      implementation_->input_mirror.touch_active(event.surface);
  if (implementation_->input_mirror.accept(event, instance->state->allocation(),
                                            active) !=
      surface::InputValidation::accepted)
    return failure(RuntimeFailure::invalid_input,
                   "input failed the global sequence/transition mirror");
  const auto device_pixel_ratio = instance->device_pixel_ratio;
  std::visit(
      [&](const auto &payload) {
        using Event = std::decay_t<decltype(payload)>;
        if constexpr (std::is_same_v<Event, surface::PointerMotion>) {
          const auto point = input_position(payload.position,
                                            device_pixel_ratio);
          QMouseEvent translated(
              QEvent::MouseMove, point, point, Qt::NoButton,
              static_cast<Qt::MouseButtons>(payload.buttons),
              static_cast<Qt::KeyboardModifiers>(payload.modifiers));
          QCoreApplication::sendEvent(&instance->window, &translated);
        } else if constexpr (std::is_same_v<Event, surface::PointerButton>) {
          const auto point = input_position(payload.position,
                                            device_pixel_ratio);
          const bool pressed = payload.state == surface::ButtonState::pressed;
          QMouseEvent translated(
              pressed ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease,
              point, point,
              static_cast<Qt::MouseButton>(payload.button),
              static_cast<Qt::MouseButtons>(payload.buttons),
              static_cast<Qt::KeyboardModifiers>(payload.modifiers));
          QCoreApplication::sendEvent(&instance->window, &translated);
        } else if constexpr (std::is_same_v<Event, surface::Wheel>) {
          const auto point = input_position(payload.position,
                                            device_pixel_ratio);
          const QPoint pixel_delta(
              qRound(static_cast<qreal>(payload.pixel_delta_x_q16) / 65536.0 *
                     device_pixel_ratio),
              qRound(static_cast<qreal>(payload.pixel_delta_y_q16) / 65536.0 *
                     device_pixel_ratio));
          QWheelEvent translated(
              point, point, pixel_delta,
              QPoint(payload.angle_delta_x, payload.angle_delta_y),
              static_cast<Qt::MouseButtons>(payload.buttons),
              static_cast<Qt::KeyboardModifiers>(payload.modifiers),
              scroll_phase(payload.phase), payload.inverted,
              Qt::MouseEventNotSynthesized);
          QCoreApplication::sendEvent(&instance->window, &translated);
        } else if constexpr (std::is_same_v<Event, surface::Key>) {
          const bool pressed = payload.state == surface::ButtonState::pressed;
          QKeyEvent translated(
              pressed ? QEvent::KeyPress : QEvent::KeyRelease,
              static_cast<int>(payload.key),
              static_cast<Qt::KeyboardModifiers>(payload.modifiers),
              payload.native_scan_code, 0, 0,
              QString::fromUtf8(payload.text.data(),
                                static_cast<qsizetype>(payload.text.size())),
              payload.auto_repeat, 1);
          QCoreApplication::sendEvent(&instance->window, &translated);
        } else if constexpr (std::is_same_v<Event, surface::TextCommit>) {
          QInputMethodEvent translated;
          translated.setCommitString(
              QString::fromUtf8(payload.text.data(),
                                static_cast<qsizetype>(payload.text.size())),
              payload.replacement_start,
              static_cast<int>(payload.replacement_length));
          QCoreApplication::sendEvent(&instance->window, &translated);
        } else if constexpr (std::is_same_v<Event, surface::TouchFrame>) {
          implementation_->touch_injector.deliver(instance->window, payload,
                                                  device_pixel_ratio);
        } else if constexpr (std::is_same_v<Event, surface::FocusChanged>) {
          if (payload.focused)
            instance->root_item->forceActiveFocus(Qt::OtherFocusReason);
          else
            implementation_->cancel_input(*instance, touch_was_active);
        } else {
          implementation_->cancel_input(*instance, touch_was_active);
        }
      },
      event.payload);
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
  instance->image.fill(Qt::transparent);
  instance->render_control.polishItems();
  instance->render_control.sync();
  instance->render_control.render();
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
  return implementation_->headless_root_item != nullptr ||
         !implementation_->surfaces.empty();
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
  return implementation_->input_mirror.focused_surface().has_value();
}

bool WorkerRuntime::render_requested() const {
  return std::ranges::any_of(implementation_->surfaces,
                             [](const auto &entry) {
                               return entry->dirty;
                             });
}

std::size_t WorkerRuntime::object_count() const {
  std::size_t total = 0;
  if (implementation_->headless_root_item != nullptr)
    total = descendants(implementation_->headless_root_item,
                        kMaximumQmlObjects + 1);
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
