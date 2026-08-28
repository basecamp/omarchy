#include "worker_runtime.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QEventPoint>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QKeyEvent>
#include <QLibraryInfo>
#include <QMouseEvent>
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

class ResourceInterceptor final : public QQmlAbstractUrlInterceptor {
public:
  ResourceInterceptor(std::filesystem::path plugin_root,
                      std::filesystem::path qt_root)
      : plugin_root_(std::move(plugin_root)), qt_root_(std::move(qt_root)) {}

  QUrl intercept(const QUrl &url, DataType) override {
    if (url.scheme() == QStringLiteral("qrc") &&
        url.path().startsWith(QStringLiteral("/qt/qml/")))
      return url;
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
        if (first == "Qt" || first == "QtQuick")
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
  explicit Impl(std::filesystem::path requested_root)
      : source_root(std::filesystem::absolute(std::move(requested_root))
                        .lexically_normal()),
        qt_root(QLibraryInfo::path(QLibraryInfo::QmlImportsPath).toStdString()),
        interceptor(source_root, qt_root), software_backend([] {
          QQuickWindow::setGraphicsApi(QSGRendererInterface::Software);
          return true;
        }()),
        render_control(), window(&render_control) {
    engine.addUrlInterceptor(&interceptor);
    engine.setImportPathList({QString::fromStdString(source_root.string()),
                              QLibraryInfo::path(QLibraryInfo::QmlImportsPath),
                              QStringLiteral("qrc:/qt/qml")});
    window.setColor(Qt::transparent);
    QObject::connect(&render_control, &QQuickRenderControl::renderRequested,
                     [this] { dirty = true; });
    QObject::connect(&render_control, &QQuickRenderControl::sceneChanged,
                     [this] { dirty = true; });
  }

  std::filesystem::path source_root;
  std::filesystem::path qt_root;
  ResourceInterceptor interceptor;
  QQmlEngine engine;
  [[maybe_unused]] bool software_backend;
  QQuickRenderControl render_control;
  QQuickWindow window;
  std::unique_ptr<QQmlComponent> component;
  QQuickItem *root_item = nullptr;
  bool profile_selected = false;
  std::uint32_t maximum_pixel_dimension = 0;
  std::uint64_t maximum_frame_bytes = 0;
  bool focused = false;
  std::optional<surface::SurfaceState> state;
  std::optional<surface::InputGate> input_gate;
  std::optional<surface::FocusGate> focus_gate;
  Mapping mapping;
  QImage image;
  std::array<std::uint64_t, surface::kSlotCount> slot_sequences{};
  std::uint64_t frame_sequence = 0;
  std::uint32_t next_slot = 0;
  bool dirty = true;
  std::string last_error;
};

WorkerRuntime::WorkerRuntime(std::filesystem::path source_root)
    : implementation_(std::make_unique<Impl>(std::move(source_root))) {}

WorkerRuntime::~WorkerRuntime() = default;

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

RuntimeResult WorkerRuntime::load_entry(std::string entry_path) {
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
  implementation_->component = std::make_unique<QQmlComponent>(
      &implementation_->engine,
      QUrl::fromLocalFile(QString::fromStdString(entry.string())),
      QQmlComponent::PreferSynchronous);
  if (!implementation_->component->isReady()) {
    implementation_->last_error =
        implementation_->component->errorString().left(2048).toStdString();
    if (implementation_->last_error.empty())
      implementation_->last_error =
          "QML entry did not resolve synchronously from allowed resources";
    return failure(RuntimeFailure::qml_load_failed,
                   implementation_->last_error);
  }
  QObject *created = implementation_->component->create();
  auto *item = qobject_cast<QQuickItem *>(created);
  if (item == nullptr) {
    delete created;
    return failure(RuntimeFailure::root_not_item,
                   "QML entry root must be a QQuickItem, not a window");
  }
  if (descendants(item, kMaximumQmlObjects + 1) > kMaximumQmlObjects) {
    delete item;
    return failure(RuntimeFailure::object_limit,
                   "QML object limit exceeded during creation");
  }
  if (implementation_->root_item != nullptr)
    delete implementation_->root_item;
  implementation_->root_item = item;
  item->setParent(&implementation_->engine);
  return {};
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
  if (implementation_->root_item == nullptr) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::qml_load_failed,
                   "QML must load before allocation");
  }
  if (implementation_->state) {
    close(mapping_descriptor);
    return failure(RuntimeFailure::surface_already_allocated,
                   "worker permits one host-owned surface");
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
      !implementation_->mapping.assign(
          mapping_descriptor,
          static_cast<std::size_t>(allocation.mapping_bytes)) ||
      !surface::initialize_frame_mapping(implementation_->mapping.bytes(),
                                         allocation))
    return failure(RuntimeFailure::mapping_invalid,
                   "shared frame mapping is not exact writable memory");
  implementation_->image = QImage(static_cast<int>(allocation.pixel_width),
                                  static_cast<int>(allocation.pixel_height),
                                  QImage::Format_RGBA8888_Premultiplied);
  if (implementation_->image.isNull() ||
      static_cast<std::uint32_t>(implementation_->image.bytesPerLine()) !=
          allocation.stride ||
      static_cast<std::uint64_t>(implementation_->image.sizeInBytes()) !=
          allocation.frame_bytes) {
    implementation_->mapping.reset();
    return failure(RuntimeFailure::allocation_invalid,
                   "QImage layout does not match trusted allocation");
  }
  implementation_->image.setDevicePixelRatio(
      static_cast<qreal>(allocation.dpr_numerator) /
      static_cast<qreal>(allocation.dpr_denominator));
  implementation_->window.setGeometry(
      0, 0, static_cast<int>(allocation.logical_width),
      static_cast<int>(allocation.logical_height));
  implementation_->root_item->setParentItem(
      implementation_->window.contentItem());
  implementation_->root_item->setSize(
      QSizeF(allocation.logical_width, allocation.logical_height));
  auto target = QQuickRenderTarget::fromPaintDevice(&implementation_->image);
  target.setDevicePixelRatio(implementation_->image.devicePixelRatio());
  implementation_->window.setRenderTarget(target);
  if (!state->apply(surface::SurfaceTransition::activate)) {
    implementation_->mapping.reset();
    return failure(RuntimeFailure::invalid_transition,
                   "surface activation failed");
  }
  implementation_->state = std::move(state);
  implementation_->input_gate = std::move(input_gate);
  implementation_->focus_gate = std::move(focus_gate);
  implementation_->dirty = true;
  return {};
}

RuntimeResult WorkerRuntime::suspend(surface::SurfaceKey key) {
  if (!implementation_->state ||
      implementation_->state->allocation().surface != key)
    return failure(RuntimeFailure::stale_surface, "stale surface suspend");
  if (!implementation_->state->apply(surface::SurfaceTransition::suspend))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot suspend in current phase");
  implementation_->focused = false;
  return {};
}

RuntimeResult WorkerRuntime::resume(surface::SurfaceKey key) {
  if (!implementation_->state ||
      implementation_->state->allocation().surface != key)
    return failure(RuntimeFailure::stale_surface, "stale surface resume");
  if (!implementation_->state->apply(surface::SurfaceTransition::resume))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot resume in current phase");
  implementation_->dirty = true;
  return {};
}

RuntimeResult WorkerRuntime::release(surface::SurfaceKey key) {
  if (!implementation_->state ||
      implementation_->state->allocation().surface != key)
    return failure(RuntimeFailure::stale_surface, "stale surface release");
  if (!implementation_->state->apply(
          surface::SurfaceTransition::begin_destroy) ||
      !implementation_->state->apply(
          surface::SurfaceTransition::finish_destroy))
    return failure(RuntimeFailure::invalid_transition,
                   "surface cannot release in current phase");
  implementation_->root_item->setParentItem(nullptr);
  implementation_->mapping.reset();
  implementation_->image = {};
  implementation_->input_gate.reset();
  implementation_->focus_gate.reset();
  implementation_->state.reset();
  implementation_->focused = false;
  return {};
}

RuntimeResult WorkerRuntime::focus(const surface::FocusEvent &event) {
  if (!implementation_->state || !implementation_->focus_gate)
    return failure(RuntimeFailure::invalid_input, "surface is not allocated");
  const bool active =
      implementation_->state->phase() == surface::SurfacePhase::active;
  if (implementation_->focus_gate->accept(event, active) !=
      surface::InputValidation::accepted)
    return failure(RuntimeFailure::invalid_input,
                   "focus event failed the monotonic surface gate");
  implementation_->focused = event.focused;
  if (event.focused)
    implementation_->root_item->forceActiveFocus(Qt::OtherFocusReason);
  else
    implementation_->root_item->setFocus(false, Qt::OtherFocusReason);
  return {};
}

RuntimeResult WorkerRuntime::input(const surface::InputEvent &event) {
  if (!implementation_->state || !implementation_->input_gate)
    return failure(RuntimeFailure::invalid_input, "surface is not allocated");
  const bool active =
      implementation_->state->phase() == surface::SurfacePhase::active;
  if (implementation_->input_gate->accept(event, active,
                                          implementation_->focused) !=
      surface::InputValidation::accepted)
    return failure(RuntimeFailure::invalid_input,
                   "input failed the monotonic surface/focus gate");
  const QPointF point(static_cast<qreal>(event.x_q16) / 65536.0,
                      static_cast<qreal>(event.y_q16) / 65536.0);
  if (event.kind == surface::InputKind::pointer_motion) {
    QMouseEvent translated(QEvent::MouseMove, point, point, Qt::NoButton,
                           Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  } else if (event.kind == surface::InputKind::pointer_button) {
    const auto button = mouse_button(event.code);
    const bool pressed = event.state == static_cast<std::uint32_t>(
                                            surface::ButtonState::pressed);
    QMouseEvent translated(
        pressed ? QEvent::MouseButtonPress : QEvent::MouseButtonRelease, point,
        point, button, pressed ? button : Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  } else if (event.kind == surface::InputKind::scroll) {
    const QPoint pixel_delta(event.delta_x_q16 / 65536,
                             event.delta_y_q16 / 65536);
    QWheelEvent translated(point, point, pixel_delta, {}, Qt::NoButton,
                           Qt::NoModifier, Qt::ScrollUpdate, false);
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
        type, nullptr, Qt::NoModifier,
        {QEventPoint(static_cast<int>(event.code), state, point, point)});
    QCoreApplication::sendEvent(&implementation_->window, &translated);
  }
  implementation_->dirty = true;
  return {};
}

std::optional<PublishedFrame> WorkerRuntime::render() {
  if (!active() || implementation_->root_item == nullptr)
    return std::nullopt;
  implementation_->dirty = false;
  const auto count = object_count();
  if (count > kMaximumQmlObjects) {
    implementation_->last_error = "QML object limit exceeded before render";
    return std::nullopt;
  }
  implementation_->image.fill(Qt::transparent);
  implementation_->render_control.polishItems();
  implementation_->render_control.sync();
  implementation_->render_control.render();
  const auto &allocation = implementation_->state->allocation();
  const auto slot = implementation_->next_slot;
  implementation_->next_slot = (slot + 1) % surface::kSlotCount;
  auto &slot_sequence = implementation_->slot_sequences[slot];
  if (slot_sequence > std::numeric_limits<std::uint64_t>::max() - 2 ||
      implementation_->frame_sequence ==
          std::numeric_limits<std::uint64_t>::max()) {
    implementation_->last_error = "frame sequence exhausted";
    return std::nullopt;
  }
  slot_sequence += 2;
  ++implementation_->frame_sequence;
  const auto *pixel_bytes =
      reinterpret_cast<const std::byte *>(implementation_->image.constBits());
  const std::span<const std::byte> pixels(
      pixel_bytes,
      static_cast<std::size_t>(implementation_->image.sizeInBytes()));
  if (surface::publish_frame(implementation_->mapping.bytes(), allocation, slot,
                             slot_sequence, implementation_->frame_sequence,
                             pixels) != surface::PublishResult::published) {
    implementation_->last_error = "shared frame publication failed";
    return std::nullopt;
  }
  return PublishedFrame{
      .ready = {.surface = allocation.surface,
                .slot = slot,
                .slot_sequence = slot_sequence,
                .frame_sequence = implementation_->frame_sequence},
      .rendered_objects = count};
}

bool WorkerRuntime::loaded() const {
  return implementation_->root_item != nullptr;
}

bool WorkerRuntime::allocated() const {
  return implementation_->state.has_value();
}

bool WorkerRuntime::active() const {
  return implementation_->state &&
         implementation_->state->phase() == surface::SurfacePhase::active;
}

bool WorkerRuntime::focused() const { return implementation_->focused; }

bool WorkerRuntime::render_requested() const { return implementation_->dirty; }

std::size_t WorkerRuntime::object_count() const {
  return descendants(implementation_->root_item, kMaximumQmlObjects + 1);
}

const std::string &WorkerRuntime::last_error() const {
  return implementation_->last_error;
}

} // namespace omarchy::plugin_runtime::worker
