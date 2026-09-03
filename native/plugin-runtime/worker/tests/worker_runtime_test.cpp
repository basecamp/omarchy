#include "worker_runtime.hpp"

#include "qt_touch_injector.hpp"
#include "omarchy/plugin_runtime/sandbox/policy.h"

#include <QBuffer>
#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QLibraryInfo>
#include <QQuickItem>
#include <QQuickRenderControl>
#include <QQuickWindow>
#include <QScreen>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTimer>
#include <QTouchEvent>
#include <QWheelEvent>

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;

void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

std::filesystem::path fixture(const char *name) {
  return std::filesystem::path(WORKER_FIXTURE_ROOT) / name;
}

class ExactQmlTree {
public:
  ExactQmlTree() {
    std::array<char, 40> pattern{};
    constexpr std::string_view value = "/tmp/omarchy-qml-imports-XXXXXX";
    std::ranges::copy(value, pattern.begin());
    root_ = mkdtemp(pattern.data());
    require(!root_.empty(), "exact QML tree temp directory failed");
    const std::filesystem::path source(
        QLibraryInfo::path(QLibraryInfo::QmlImportsPath).toStdString());
    for (const auto &relative :
         omarchy::plugin_runtime::sandbox::trusted_qml_files()) {
      const auto destination = root_ / relative;
      std::filesystem::create_directories(destination.parent_path());
      std::filesystem::copy_file(source / relative, destination);
    }
  }
  ~ExactQmlTree() {
    std::error_code error;
    std::filesystem::remove_all(root_, error);
  }
  ExactQmlTree(const ExactQmlTree &) = delete;
  ExactQmlTree &operator=(const ExactQmlTree &) = delete;
  [[nodiscard]] const std::filesystem::path &root() const { return root_; }

private:
  std::filesystem::path root_;
};

class Mapping {
public:
  Mapping(int descriptor, std::size_t size) : size_(size) {
    address_ = static_cast<std::byte *>(
        mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0));
    require(address_ != MAP_FAILED, "test mapping failed");
  }
  ~Mapping() {
    if (address_ != MAP_FAILED)
      munmap(address_, size_);
  }
  [[nodiscard]] std::span<const std::byte> bytes() const {
    return {address_, size_};
  }

private:
  std::byte *address_ = reinterpret_cast<std::byte *>(MAP_FAILED);
  std::size_t size_ = 0;
};

class InputEventProbe final : public QObject {
public:
  QEvent::Type type = QEvent::None;
  QPointF position;
  QPoint pixel_delta;
  QPoint angle_delta;
  Qt::MouseButton button = Qt::NoButton;
  Qt::MouseButtons buttons = Qt::NoButton;
  Qt::KeyboardModifiers modifiers = Qt::NoModifier;
  Qt::ScrollPhase phase = Qt::NoScrollPhase;
  bool inverted = false;
  int key = 0;
  quint32 native_scan_code = 0;
  QString text;
  bool auto_repeat = false;
  int replacement_start = 0;
  int replacement_length = 0;
  QList<QEventPoint> touch_points;
  std::size_t touch_cancel_count = 0;

protected:
  bool eventFilter(QObject *, QEvent *event) override {
    if (const auto *mouse = dynamic_cast<QMouseEvent *>(event)) {
      type = event->type();
      position = mouse->position();
      button = mouse->button();
      buttons = mouse->buttons();
      modifiers = mouse->modifiers();
    } else if (const auto *wheel = dynamic_cast<QWheelEvent *>(event)) {
      type = event->type();
      position = wheel->position();
      pixel_delta = wheel->pixelDelta();
      angle_delta = wheel->angleDelta();
      buttons = wheel->buttons();
      modifiers = wheel->modifiers();
      phase = wheel->phase();
      inverted = wheel->inverted();
    } else if (const auto *key_event = dynamic_cast<QKeyEvent *>(event)) {
      type = event->type();
      key = key_event->key();
      native_scan_code = key_event->nativeScanCode();
      modifiers = key_event->modifiers();
      text = key_event->text();
      auto_repeat = key_event->isAutoRepeat();
    } else if (const auto *commit =
                   dynamic_cast<QInputMethodEvent *>(event)) {
      type = event->type();
      text = commit->commitString();
      replacement_start = commit->replacementStart();
      replacement_length = commit->replacementLength();
    } else if (const auto *touch = dynamic_cast<QTouchEvent *>(event)) {
      type = event->type();
      if (event->type() == QEvent::TouchCancel)
        ++touch_cancel_count;
      modifiers = touch->modifiers();
      touch_points = touch->points();
    }
    return false;
  }
};

void render_and_input() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  const auto prepared = runtime.prepare_trusted_qt_types();
  if (!prepared)
    throw std::runtime_error("trusted Qt type preparation failed: " +
                             prepared.detail);
  require(static_cast<bool>(runtime.load_manifest_entry()),
          "schema-v2 QML fixture did not load");
  require(runtime.loaded() && runtime.object_count() > 2,
          "arbitrary QML object scene was not retained");
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "software profile was not selected");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "page size unavailable");
  const auto allocation =
      surface::make_allocation({.id = 41, .generation = 9}, 64, 32, 64, 32, 1,
                               1, static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "test allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "worker-frame-test", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "test memfd failed");
  Mapping mapping(descriptor,
                  static_cast<std::size_t>(allocation->mapping_bytes));
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0, "worker descriptor duplication failed");
  const auto allocation_result =
      runtime.allocate(*allocation, worker_descriptor);
  if (!allocation_result)
    throw std::runtime_error("worker rejected exact writable allocation: " +
                             allocation_result.detail);
  require(runtime.active() && runtime.render_requested(),
          "allocated scene is not renderable");
  const auto published = runtime.render();
  require(published.has_value() && published->ready.frame_sequence == 1 &&
              published->ready.slot_sequence == 2,
          "first frame did not publish with canonical sequences");
  auto consumer = surface::FrameConsumer::create(*allocation);
  require(consumer.has_value() &&
              consumer->consume(mapping.bytes(), published->ready) ==
                  surface::ConsumeResult::accepted,
          "trusted consumer rejected worker frame");
  const auto *frame = consumer->last_frame();
  require(frame != nullptr && frame->pixels.size() == allocation->frame_bytes,
          "worker frame bytes are incomplete");
  require(
      std::ranges::any_of(
          frame->pixels, [](std::byte value) { return value != std::byte{0}; }),
      "arbitrary QML rendered only transparent pixels");
  const auto first_pixels = frame->pixels;
  bool animation_changed = false;
  for (int sample = 0; sample < 6 && !animation_changed; ++sample) {
    QEventLoop animation_loop;
    QTimer::singleShot(40, &animation_loop, &QEventLoop::quit);
    animation_loop.exec();
    const auto animated = runtime.render();
    require(animated.has_value() &&
                consumer->consume(mapping.bytes(), animated->ready) ==
                    surface::ConsumeResult::accepted,
            "animated arbitrary QML frame was not consumable");
    animation_changed = consumer->last_frame()->pixels != first_pixels;
  }
  require(animation_changed,
          "animated arbitrary QML did not publish a distinct frame");

  require(static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = 1,
               .payload = surface::FocusChanged{.focused = true}})),
      "trusted focus event failed");
  surface::InputEvent press{
      .surface = allocation->surface,
      .sequence = 2,
      .payload = surface::PointerButton{
          .position = {.x_q16 = 10U << 16, .y_q16 = 10U << 16},
          .button = static_cast<std::uint32_t>(Qt::LeftButton),
          .state = surface::ButtonState::pressed,
          .buttons = static_cast<std::uint32_t>(Qt::LeftButton)},
  };
  require(static_cast<bool>(runtime.input(press)),
          "focused pointer input failed");
  require(!static_cast<bool>(runtime.input(press)),
          "replayed input sequence was accepted");
  auto release = press;
  release.sequence = 3;
  release.payload = surface::PointerButton{
      .position = {.x_q16 = 10U << 16, .y_q16 = 10U << 16},
      .button = static_cast<std::uint32_t>(Qt::LeftButton),
      .state = surface::ButtonState::released,
      .buttons = 0};
  require(static_cast<bool>(runtime.input(release)),
          "trusted pointer release failed");
  surface::InputEvent touch{
      .surface = allocation->surface,
      .sequence = 4,
      .payload = surface::TouchFrame{
          .phase = surface::TouchFramePhase::begin,
          .points = {{surface::TouchPoint{
              .id = 1,
              .state = surface::TouchPointState::pressed,
              .position = {.x_q16 = 10U << 16, .y_q16 = 10U << 16}}}},
          .count = 1},
  };
  require(static_cast<bool>(runtime.input(touch)),
          "trusted touch begin failed");
  touch.sequence = 5;
  touch.payload = surface::TouchFrame{
      .phase = surface::TouchFramePhase::update,
      .points = {{surface::TouchPoint{
          .id = 1,
          .state = surface::TouchPointState::updated,
          .position = {.x_q16 = 11U << 16, .y_q16 = 11U << 16}}}},
      .count = 1};
  require(static_cast<bool>(runtime.input(touch)),
          "trusted touch update failed");
  touch.sequence = 6;
  touch.payload = surface::TouchFrame{
      .phase = surface::TouchFramePhase::end,
      .points = {{surface::TouchPoint{
          .id = 1,
          .state = surface::TouchPointState::released,
          .position = {.x_q16 = 11U << 16, .y_q16 = 11U << 16}}}},
      .count = 1};
  require(static_cast<bool>(runtime.input(touch)), "trusted touch end failed");
  require(
      static_cast<bool>(runtime.input(
          {.surface = allocation->surface,
           .sequence = 7,
           .payload = surface::FocusChanged{.focused = false}})) &&
          !runtime.focused(),
      "input lifecycle did not end unfocused");
  require(runtime.render_requested(), "input did not dirty the scene");
  require(runtime.render().has_value(), "input-driven frame did not publish");

  require(static_cast<bool>(runtime.suspend(allocation->surface)),
          "surface did not suspend");
  require(!runtime.render().has_value(), "suspended surface rendered");
  require(!runtime.resume({.id = 41, .generation = 8}),
          "stale surface generation resumed");
  require(static_cast<bool>(runtime.resume(allocation->surface)),
          "surface did not resume");
  require(runtime.render().has_value(), "resumed surface did not render");
  require(static_cast<bool>(runtime.release(allocation->surface)),
          "surface did not release");
  require(!runtime.allocated(), "released mapping remained allocated");
}

void headless_entry_has_no_surface_authority() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(runtime.load_entry("Main.qml")) &&
              runtime.loaded() && runtime.object_count() > 2,
          "headless arbitrary QML did not remain alive");
  require(!runtime.surface_key("") &&
              !static_cast<bool>(runtime.bind_surface(
                  "", {.id = 91, .generation = 7})),
          "headless QML acquired a name-to-surface binding");
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "headless QML profile selection failed");
  const auto page_size = sysconf(_SC_PAGESIZE);
  const auto allocation = surface::make_allocation(
      {.id = 91, .generation = 7}, 32, 16, 32, 16, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(page_size > 0 && allocation.has_value(),
          "headless allocation fixture failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "headless-frame-test", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "headless allocation descriptor failed");
  const auto result = runtime.allocate(*allocation, descriptor);
  require(!result && result.failure == worker::RuntimeFailure::stale_surface &&
              fcntl(descriptor, F_GETFD) < 0 && errno == EBADF &&
              !runtime.allocated() && !runtime.active() &&
              !runtime.render().has_value(),
          "headless QML entered surface allocation or render routing");
}

void typed_input_projects_exact_qt_events() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(runtime.load_manifest_entry()) &&
              static_cast<bool>(runtime.select_software_profile(
                  surface::software_profile_offer())),
          "typed-input scene did not load");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "typed-input page size unavailable");
  const auto allocation = surface::make_allocation(
      {.id = 44, .generation = 12}, 64, 32, 128, 64, 2, 1,
      static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "typed-input allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "worker-input-test", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "typed-input memfd failed");
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 &&
              static_cast<bool>(runtime.allocate(*allocation,
                                                 worker_descriptor)),
          "typed-input allocation was rejected");

  InputEventProbe probe;
  QCoreApplication::instance()->installEventFilter(&probe);
  std::uint64_t sequence = 1;
  const auto accepted = [&](surface::InputPayload payload) {
    const bool result = static_cast<bool>(runtime.input(
        {.surface = allocation->surface,
         .sequence = sequence,
         .payload = std::move(payload)}));
    ++sequence;
    return result;
  };

  require(accepted(surface::FocusChanged{.focused = true}) &&
              runtime.focused(),
          "typed focus acquisition was not reconstructed");
  require(accepted(surface::PointerMotion{
              .position = {.x_q16 = (3U << 16) + (1U << 15),
                           .y_q16 = (4U << 16) + (1U << 14)},
              .buttons = 0,
              .modifiers = static_cast<std::uint32_t>(Qt::ShiftModifier)}) &&
              probe.type == QEvent::MouseMove &&
              probe.position == QPointF(7.0, 8.5) &&
              probe.buttons == Qt::NoButton &&
              probe.modifiers == Qt::ShiftModifier,
          "pointer motion lost position, buttons, or modifiers");
  const auto press = surface::PointerButton{
      .position = {.x_q16 = 5U << 16, .y_q16 = 6U << 16},
      .button = static_cast<std::uint32_t>(Qt::RightButton),
      .state = surface::ButtonState::pressed,
      .buttons = static_cast<std::uint32_t>(Qt::RightButton),
      .modifiers = static_cast<std::uint32_t>(Qt::ControlModifier)};
  require(accepted(press) && probe.type == QEvent::MouseButtonPress &&
              probe.position == QPointF(10.0, 12.0) &&
              probe.button == Qt::RightButton &&
              probe.buttons == Qt::RightButton &&
              probe.modifiers == Qt::ControlModifier,
          "pointer button lost exact Qt masks");
  require(accepted(surface::Wheel{
              .position = {.x_q16 = 5U << 16, .y_q16 = 6U << 16},
              .pixel_delta_x_q16 = (1 << 16) + (1 << 15),
              .pixel_delta_y_q16 = -(2 << 16),
              .angle_delta_x = 120,
              .angle_delta_y = -240,
              .phase = surface::WheelPhase::discrete,
              .buttons = static_cast<std::uint32_t>(Qt::RightButton),
              .modifiers = static_cast<std::uint32_t>(Qt::AltModifier),
              .inverted = true}) &&
              probe.type == QEvent::Wheel &&
              probe.pixel_delta == QPoint(3, -4) &&
              probe.angle_delta == QPoint(120, -240) &&
              probe.phase == Qt::NoScrollPhase && probe.inverted &&
              probe.buttons == Qt::RightButton &&
              probe.modifiers == Qt::AltModifier,
          "discrete wheel event lost deltas, phase, or masks");
  for (const auto [input_phase, qt_phase] :
       {std::pair{surface::WheelPhase::begin, Qt::ScrollBegin},
        std::pair{surface::WheelPhase::update, Qt::ScrollUpdate},
        std::pair{surface::WheelPhase::momentum, Qt::ScrollMomentum},
        std::pair{surface::WheelPhase::end, Qt::ScrollEnd}}) {
    require(accepted(surface::Wheel{
                .position = {.x_q16 = 5U << 16, .y_q16 = 6U << 16},
                .phase = input_phase,
                .buttons = static_cast<std::uint32_t>(Qt::RightButton)}) &&
                probe.type == QEvent::Wheel && probe.phase == qt_phase,
            "continuous wheel phase was not reconstructed exactly");
  }

  const auto key_press = surface::Key{
      .key = static_cast<std::uint32_t>(Qt::Key_A),
      .native_scan_code = 30,
      .modifiers = static_cast<std::uint32_t>(Qt::ShiftModifier),
      .state = surface::ButtonState::pressed,
      .auto_repeat = false,
      .text = "A"};
  require(accepted(key_press) && probe.type == QEvent::KeyPress &&
              probe.key == Qt::Key_A && probe.native_scan_code == 30 &&
              probe.modifiers == Qt::ShiftModifier && probe.text == "A" &&
              !probe.auto_repeat,
          "key press lost code, scan code, modifiers, or text");
  auto repeated = key_press;
  repeated.auto_repeat = true;
  require(accepted(repeated) && probe.type == QEvent::KeyPress &&
              probe.auto_repeat,
          "autorepeat press was not normalized to a repeated Qt key press");
  auto invalid_repeat_release = repeated;
  invalid_repeat_release.state = surface::ButtonState::released;
  require(!static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = sequence,
               .payload = invalid_repeat_release})),
          "autorepeat release crossed the worker mirror");
  require(accepted(surface::TextCommit{.text = std::string("\xc3\xa9", 2),
                                       .replacement_start = -1,
                                       .replacement_length = 1}) &&
              probe.type == QEvent::InputMethod && probe.text == QString(u"é") &&
              probe.replacement_start == -1 &&
              probe.replacement_length == 1,
          "text commit lost UTF-8 or replacement bounds");
  auto key_release = key_press;
  key_release.state = surface::ButtonState::released;
  key_release.text.clear();
  require(accepted(key_release) && probe.type == QEvent::KeyRelease &&
              !probe.auto_repeat,
          "final non-repeat key release was not reconstructed");

  surface::TouchFrame touch_begin{
      .phase = surface::TouchFramePhase::begin,
      .points = {{
          {.id = 1,
           .state = surface::TouchPointState::pressed,
           .position = {.x_q16 = 8U << 16, .y_q16 = 9U << 16}},
          {.id = 2,
           .state = surface::TouchPointState::pressed,
           .position = {.x_q16 = 12U << 16, .y_q16 = 13U << 16}},
      }},
      .count = 2,
      .modifiers = static_cast<std::uint32_t>(Qt::MetaModifier)};
  require(accepted(touch_begin) && probe.type == QEvent::TouchBegin &&
              probe.touch_points.size() == 2 &&
              probe.touch_points[0].id() == 1 &&
              probe.touch_points[0].state() == QEventPoint::State::Pressed &&
              probe.touch_points[1].id() == 2 &&
              probe.touch_points[1].state() == QEventPoint::State::Pressed &&
              probe.modifiers == Qt::MetaModifier,
          "atomic touch begin lost points, states, or modifiers");
  auto touch_update = touch_begin;
  touch_update.phase = surface::TouchFramePhase::update;
  touch_update.points[0].state = surface::TouchPointState::updated;
  touch_update.points[0].position.x_q16 = 9U << 16;
  touch_update.points[1].state = surface::TouchPointState::stationary;
  require(accepted(touch_update) && probe.type == QEvent::TouchUpdate &&
              probe.touch_points.size() == 2 &&
              probe.touch_points[0].state() == QEventPoint::State::Updated &&
              probe.touch_points[1].state() ==
                  QEventPoint::State::Stationary,
          "atomic touch update was split or lost point state");
  auto touch_end = touch_update;
  touch_end.phase = surface::TouchFramePhase::end;
  touch_end.points[0].state = surface::TouchPointState::released;
  touch_end.points[1].state = surface::TouchPointState::released;
  require(accepted(touch_end) && probe.type == QEvent::TouchEnd &&
              probe.touch_points.size() == 2,
          "atomic touch end was not reconstructed");

  auto pointer_release = press;
  pointer_release.state = surface::ButtonState::released;
  pointer_release.buttons = 0;
  require(accepted(pointer_release), "pointer release was rejected");
  require(accepted(key_press), "pre-cancel key press was rejected");
  require(accepted(touch_begin), "pre-cancel touch frame was rejected");
  require(accepted(surface::Cancel{}) && !runtime.focused(),
          "cancel did not clear worker focus and mirrored input");
  require(!static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = sequence,
               .payload = pointer_release})) &&
              !static_cast<bool>(runtime.input(
                  {.surface = allocation->surface,
                   .sequence = sequence,
                   .payload = key_release})),
          "cancel retained pressed button or key state");
  require(accepted(surface::FocusChanged{.focused = true}),
          "focus could not be reacquired after cancel");
  require(!static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = sequence,
               .payload = key_release})),
          "cancel retained key state after focus reacquisition");
  require(accepted(key_press) && accepted(press) && accepted(touch_begin),
          "pre-suspend input state was not established");
  require(static_cast<bool>(runtime.suspend(allocation->surface)) &&
              !runtime.focused() &&
              static_cast<bool>(runtime.resume(allocation->surface)),
          "suspend did not clear focus or resume cleanly");
  require(!static_cast<bool>(runtime.input(
              {.surface = allocation->surface,
               .sequence = sequence,
               .payload = pointer_release})) &&
              !static_cast<bool>(runtime.input(
                  {.surface = allocation->surface,
                   .sequence = sequence,
                   .payload = key_release})) &&
              !static_cast<bool>(runtime.input(
                  {.surface = allocation->surface,
                   .sequence = sequence,
                   .payload = touch_end})),
          "suspend retained pressed button, key, or touch state");
  const auto touch_cancels_before_no_touch_focus_loss =
      probe.touch_cancel_count;
  require(accepted(surface::FocusChanged{.focused = true}) &&
              !static_cast<bool>(runtime.input(
                  {.surface = allocation->surface,
                   .sequence = sequence,
                   .payload = key_release})) &&
              accepted(surface::FocusChanged{.focused = false}) &&
              probe.touch_cancel_count ==
                  touch_cancels_before_no_touch_focus_loss &&
              static_cast<bool>(runtime.release(allocation->surface)) &&
              !runtime.focused(),
          "focus or mirrored input state survived suspend/release");
  QCoreApplication::instance()->removeEventFilter(&probe);
}

void touch_injector_maps_native_global_coordinates() {
  QQuickRenderControl render_control;
  QQuickWindow window(&render_control);
  window.setGeometry(37, 53, 128, 64);
  window.contentItem()->setSize(QSizeF(128, 64));
  QQuickItem receiver(window.contentItem());
  receiver.setSize(QSizeF(128, 64));
  receiver.setAcceptTouchEvents(true);

  InputEventProbe probe;
  QCoreApplication::instance()->installEventFilter(&probe);
  worker::QtTouchInjector injector;
  injector.deliver(
      window,
      {.phase = surface::TouchFramePhase::begin,
       .points = {{
           {.id = 0,
            .state = surface::TouchPointState::pressed,
            .position = {.x_q16 = 8U << 16, .y_q16 = 6U << 16}},
       }},
       .count = 1},
      2.0);
  require(probe.type == QEvent::TouchBegin &&
              probe.touch_points.size() == 1 &&
              probe.touch_points[0].position() == QPointF(16, 12) &&
              probe.touch_points[0].globalPosition() == QPointF(53, 65),
          "QPA touch coordinates were scaled twice or lost window origin");
  const auto geometry = window.screen()->geometry();
  const auto normalized = probe.touch_points[0].normalizedPosition();
  const auto platform_scale = window.devicePixelRatio();
  const QPointF native_global(
      geometry.x() + (53.0 - geometry.x()) * platform_scale,
      geometry.y() + (65.0 - geometry.y()) * platform_scale);
  QRect native_virtual_geometry;
  for (const QScreen *screen : QGuiApplication::screens()) {
    const auto screen_geometry = screen->geometry();
    const auto scale = screen->devicePixelRatio();
    native_virtual_geometry |=
        QRect(screen_geometry.topLeft(),
              QSize(qRound(screen_geometry.width() * scale),
                    qRound(screen_geometry.height() * scale)));
  }
  require(normalized.x() > 0.0 && normalized.x() < 1.0 &&
              normalized.y() > 0.0 && normalized.y() < 1.0,
          "QPA touch did not carry normalized virtual-screen coordinates");
  if (QGuiApplication::platformName() == QStringLiteral("offscreen")) {
    const QPointF expected(
        (native_global.x() - native_virtual_geometry.x()) /
            native_virtual_geometry.width(),
        (native_global.y() - native_virtual_geometry.y()) /
            native_virtual_geometry.height());
    require(qAbs(normalized.x() - expected.x()) < 0.000001 &&
                qAbs(normalized.y() - expected.y()) < 0.000001,
            "QPA touch normalized coordinates ignored screen geometry");
  }
  injector.cancel(window);
  QCoreApplication::instance()->removeEventFilter(&probe);
}

void touch_input_reaches_qml_handlers() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  const auto loaded = runtime.load_surface_entry("touch", "Touch.qml");
  if (!loaded)
    throw std::runtime_error("touch QML did not load: " + loaded.detail);
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "touch QML profile was not selected");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "touch QML page size unavailable");
  const auto allocation = surface::make_allocation(
      {.id = 47, .generation = 13}, 64, 32, 128, 64, 2, 1,
      static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "touch QML allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "worker-touch-qml", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "touch QML frame mapping failed");
  Mapping mapping(descriptor,
                  static_cast<std::size_t>(allocation->mapping_bytes));
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 &&
              static_cast<bool>(runtime.allocate(*allocation,
                                                 worker_descriptor)),
          "touch QML allocation was rejected");
  auto consumer = surface::FrameConsumer::create(*allocation);
  require(consumer.has_value(), "touch QML consumer failed");

  const auto render_color = [&](int x, int y) {
    runtime.request_render();
    const auto frame = runtime.render();
    require(frame.has_value() &&
                consumer->consume(mapping.bytes(), frame->ready) ==
                    surface::ConsumeResult::accepted,
            "touch QML frame was not consumable");
    const QImage image(
        reinterpret_cast<const uchar *>(
            consumer->last_frame()->pixels.data()),
        static_cast<int>(allocation->pixel_width),
        static_cast<int>(allocation->pixel_height),
        static_cast<int>(allocation->stride),
        QImage::Format_RGBA8888_Premultiplied);
    return image.pixelColor(x, y);
  };

  InputEventProbe probe;
  QCoreApplication::instance()->installEventFilter(&probe);
  std::uint64_t sequence = 1;
  const auto accepted = [&](surface::InputPayload payload) {
    const bool result = static_cast<bool>(runtime.input(
        {.surface = allocation->surface,
         .sequence = sequence,
         .payload = std::move(payload)}));
    ++sequence;
    return result;
  };
  const auto focus = [&] {
    require(accepted(surface::FocusChanged{.focused = true}),
            "touch QML focus acquisition failed");
  };
  const auto two_point_begin = [] {
    return surface::TouchFrame{
        .phase = surface::TouchFramePhase::begin,
        .points = {{
            {.id = 1,
             .state = surface::TouchPointState::pressed,
             .position = {.x_q16 = 8U << 16, .y_q16 = 8U << 16}},
            {.id = 2,
             .state = surface::TouchPointState::pressed,
             .position = {.x_q16 = 20U << 16, .y_q16 = 12U << 16}},
        }},
        .count = 2};
  };

  focus();
  auto begin = two_point_begin();
  const bool begin_accepted = accepted(begin);
  const auto left_begin_color = render_color(16, 16);
  const auto right_begin_color = render_color(96, 32);
  if (!(begin_accepted && probe.type == QEvent::TouchBegin &&
              probe.touch_points.size() == 2 &&
              probe.touch_points[0].position() == QPointF(8, 8) &&
              probe.touch_points[1].position() == QPointF(20, 12) &&
              probe.touch_points[0].pressure() == 1.0 &&
              left_begin_color == QColor("#ff0000") &&
              right_begin_color == QColor("#111111"))) {
    throw std::runtime_error(
        "DPR-scaled two-point begin mismatch: accepted=" +
        std::to_string(begin_accepted) + " type=" +
        std::to_string(probe.type) + " count=" +
        std::to_string(probe.touch_points.size()) + " p0=" +
        std::to_string(probe.touch_points.empty()
                           ? -1.0
                           : probe.touch_points[0].position().x()) +
        "," +
        std::to_string(probe.touch_points.empty()
                           ? -1.0
                           : probe.touch_points[0].position().y()) +
        " colors=" + left_begin_color.name().toStdString() + "," +
        right_begin_color.name().toStdString());
  }
  auto update = begin;
  update.phase = surface::TouchFramePhase::update;
  update.points[0].state = surface::TouchPointState::updated;
  update.points[0].position = {.x_q16 = 10U << 16, .y_q16 = 9U << 16};
  update.points[1].state = surface::TouchPointState::stationary;
  auto partial_update = update;
  partial_update.count = 1;
  require(!accepted(partial_update) &&
              render_color(16, 16) == QColor("#ff0000"),
          "worker accepted a partial touch delta or delivered it to QML");
  require(accepted(update) && probe.type == QEvent::TouchUpdate &&
              probe.touch_points.size() == 2 &&
              probe.touch_points[0].state() == QEventPoint::State::Updated &&
              probe.touch_points[1].state() ==
                  QEventPoint::State::Stationary &&
              render_color(16, 16) == QColor("#00ff00"),
          "atomic touch update lost its updated or stationary contact");
  auto end = update;
  end.phase = surface::TouchFramePhase::end;
  end.points[0].state = surface::TouchPointState::released;
  end.points[1].state = surface::TouchPointState::released;
  require(accepted(end) && probe.type == QEvent::TouchEnd &&
              probe.touch_points.size() == 2 &&
              probe.touch_points[0].pressure() == 0.0 &&
              render_color(16, 16) == QColor("#0000ff"),
          "atomic two-point end missed the MultiPointTouchArea");

  surface::TouchFrame handler_begin{
      .phase = surface::TouchFramePhase::begin,
      .points = {{
          {.id = 3,
           .state = surface::TouchPointState::pressed,
           .position = {.x_q16 = 48U << 16, .y_q16 = 16U << 16}},
      }},
      .count = 1};
  require(accepted(handler_begin) &&
              render_color(96, 32) == QColor("#ff00ff"),
          "right-side touch did not activate its PointHandler");
  auto handler_end = handler_begin;
  handler_end.phase = surface::TouchFramePhase::end;
  handler_end.points[0].state = surface::TouchPointState::released;
  require(accepted(handler_end) &&
              render_color(96, 32) == QColor("#00ffff"),
          "PointHandler did not receive terminal release");

  begin = two_point_begin();
  require(accepted(begin), "pre-touch-cancel begin failed");
  auto cancels = probe.touch_cancel_count;
  require(accepted(surface::TouchFrame{
              .phase = surface::TouchFramePhase::cancel}) &&
              probe.touch_cancel_count > cancels &&
              render_color(16, 16) == QColor("#ffff00") && runtime.focused(),
          "typed touch cancel did not clear the exact QML touch stream");
  require(accepted(surface::FocusChanged{.focused = false}),
          "focus did not clear after typed touch cancel");

  focus();
  begin = two_point_begin();
  require(accepted(begin), "pre-cancel touch begin failed");
  cancels = probe.touch_cancel_count;
  const bool cancel_accepted = accepted(surface::Cancel{});
  const auto cancel_color = render_color(16, 16);
  if (!(cancel_accepted && probe.touch_cancel_count > cancels &&
        cancel_color == QColor("#ffff00")))
    throw std::runtime_error(
        "cancel QML mismatch: accepted=" +
        std::to_string(cancel_accepted) + " count=" +
        std::to_string(probe.touch_cancel_count - cancels) + " color=" +
        cancel_color.name().toStdString());

  focus();
  require(accepted(two_point_begin()), "pre-focus-loss touch begin failed");
  cancels = probe.touch_cancel_count;
  require(accepted(surface::FocusChanged{.focused = false}) &&
              probe.touch_cancel_count > cancels &&
              render_color(16, 16) == QColor("#ffff00"),
          "focus loss did not cancel QML touch state");

  focus();
  require(accepted(two_point_begin()), "pre-suspend touch begin failed");
  cancels = probe.touch_cancel_count;
  require(static_cast<bool>(runtime.suspend(allocation->surface)) &&
              probe.touch_cancel_count > cancels &&
              static_cast<bool>(runtime.resume(allocation->surface)) &&
              render_color(16, 16) == QColor("#ffff00"),
          "suspend did not cancel QML touch state before resume");

  focus();
  require(accepted(two_point_begin()), "pre-release touch begin failed");
  cancels = probe.touch_cancel_count;
  require(static_cast<bool>(runtime.release(allocation->surface)) &&
              probe.touch_cancel_count > cancels &&
              !runtime.allocated(),
          "release did not cancel QML touch state before teardown");
  QCoreApplication::instance()->removeEventFilter(&probe);
}

enum class SiblingInteraction { focused_text, pointer_grab };

void sibling_render_preserves_interaction(SiblingInteraction interaction) {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(runtime.load_surface_entry(
              "target", "InteractionState.qml")) &&
              static_cast<bool>(runtime.load_surface_entry(
                  "sibling", "InteractionState.qml")) &&
              static_cast<bool>(runtime.select_software_profile(
                  surface::software_profile_offer())),
          "sibling-render interaction surfaces did not load");
  const auto page_size = sysconf(_SC_PAGESIZE);
  const auto target = surface::make_allocation(
      {.id = 81, .generation = 15}, 64, 32, 64, 32, 1, 1,
      static_cast<std::uint64_t>(page_size));
  const auto sibling = surface::make_allocation(
      {.id = 82, .generation = 15}, 64, 32, 64, 32, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(page_size > 0 && target && sibling &&
              static_cast<bool>(runtime.bind_surface("target",
                                                     target->surface)) &&
              static_cast<bool>(runtime.bind_surface("sibling",
                                                     sibling->surface)),
          "sibling-render interaction surfaces did not bind");
  const int target_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-interaction-target", MFD_CLOEXEC));
  const int sibling_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-interaction-sibling", MFD_CLOEXEC));
  require(target_fd >= 0 && sibling_fd >= 0 &&
              ftruncate(target_fd,
                        static_cast<off_t>(target->mapping_bytes)) == 0 &&
              ftruncate(sibling_fd,
                        static_cast<off_t>(sibling->mapping_bytes)) == 0 &&
              static_cast<bool>(runtime.allocate(*target, target_fd)) &&
              static_cast<bool>(runtime.allocate(*sibling, sibling_fd)),
          "sibling-render interaction surfaces did not allocate");

  std::uint64_t sequence = 1;
  const auto accepted = [&](surface::InputPayload payload) {
    return static_cast<bool>(runtime.input(
        {.surface = target->surface,
         .sequence = sequence++,
         .payload = std::move(payload)}));
  };
  const auto render_sibling = [&] {
    runtime.request_render();
    for (int attempt = 0; attempt < 4; ++attempt) {
      const auto frame = runtime.render();
      require(frame.has_value(), "interleaved sibling frame was absent");
      if (frame->ready.surface == sibling->surface)
        return;
    }
    throw std::runtime_error("interleaved sibling surface was not rendered");
  };

  require(accepted(surface::FocusChanged{.focused = true}),
          "interaction target did not acquire focus");
  if (interaction == SiblingInteraction::focused_text) {
    require(runtime.root_object_name() ==
                "focused=true;keys=0;text=;drag=0",
            "focused child did not receive the trusted focus event");
    render_sibling();
    require(runtime.root_object_name() ==
                "focused=true;keys=0;text=;drag=0",
            "sibling render cleared the focused child");
    const surface::Key key_press{
        .key = static_cast<std::uint32_t>(Qt::Key_A),
        .native_scan_code = 30,
        .state = surface::ButtonState::pressed,
        .text = "a"};
    auto key_release = key_press;
    key_release.state = surface::ButtonState::released;
    key_release.text.clear();
    require(accepted(key_press) && accepted(key_release) &&
                accepted(surface::TextCommit{.text = "é"}),
            "focused child key or text input was rejected after sibling render");
    require(runtime.root_object_name() ==
                "focused=true;keys=1;text=é;drag=0",
            "focused child lost key or text input after sibling render");
    return;
  }

  const surface::PointerButton press{
      .position = {.x_q16 = 10U << 16, .y_q16 = 24U << 16},
      .button = static_cast<std::uint32_t>(Qt::LeftButton),
      .state = surface::ButtonState::pressed,
      .buttons = static_cast<std::uint32_t>(Qt::LeftButton)};
  require(accepted(press) &&
              runtime.root_object_name() ==
                  "focused=true;keys=0;text=;drag=1",
          "interaction target did not establish its pointer grab");
  render_sibling();
  const surface::PointerMotion motion{
      .position = {.x_q16 = 20U << 16, .y_q16 = 24U << 16},
      .buttons = static_cast<std::uint32_t>(Qt::LeftButton)};
  auto release = press;
  release.position.x_q16 = 20U << 16;
  release.state = surface::ButtonState::released;
  release.buttons = 0;
  require(accepted(motion) && accepted(release),
          "pointer drag input was rejected after sibling render");
  require(runtime.root_object_name() ==
              "focused=true;keys=0;text=;drag=3",
          "sibling render canceled the active child pointer grab");
}

void mouse_grab_cleanup_is_surface_scoped() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(
              runtime.load_surface_entry("first", "MouseGrab.qml")) &&
              static_cast<bool>(
                  runtime.load_surface_entry("second", "MouseGrab.qml")) &&
              static_cast<bool>(runtime.select_software_profile(
                  surface::software_profile_offer())),
          "mouse-grab surfaces did not load");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "mouse-grab page size unavailable");
  const auto first = surface::make_allocation(
      {.id = 45, .generation = 12}, 64, 32, 64, 32, 1, 1,
      static_cast<std::uint64_t>(page_size));
  const auto second = surface::make_allocation(
      {.id = 46, .generation = 12}, 64, 32, 64, 32, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(first && second &&
              static_cast<bool>(runtime.bind_surface("first", first->surface)) &&
              static_cast<bool>(
                  runtime.bind_surface("second", second->surface)),
          "mouse-grab surfaces did not bind");
  const int first_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-grab-first", MFD_CLOEXEC));
  const int second_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-grab-second", MFD_CLOEXEC));
  require(first_fd >= 0 && second_fd >= 0 &&
              ftruncate(first_fd,
                        static_cast<off_t>(first->mapping_bytes)) == 0 &&
              ftruncate(second_fd,
                        static_cast<off_t>(second->mapping_bytes)) == 0,
          "mouse-grab frame mappings failed");
  Mapping first_mapping(first_fd,
                        static_cast<std::size_t>(first->mapping_bytes));
  Mapping second_mapping(second_fd,
                         static_cast<std::size_t>(second->mapping_bytes));
  const int first_worker_fd = fcntl(first_fd, F_DUPFD_CLOEXEC, 64);
  const int second_worker_fd = fcntl(second_fd, F_DUPFD_CLOEXEC, 64);
  close(first_fd);
  close(second_fd);
  require(first_worker_fd >= 0 && second_worker_fd >= 0 &&
              static_cast<bool>(runtime.allocate(*first, first_worker_fd)) &&
              static_cast<bool>(runtime.allocate(*second, second_worker_fd)),
          "mouse-grab allocations failed");
  auto first_consumer = surface::FrameConsumer::create(*first);
  auto second_consumer = surface::FrameConsumer::create(*second);
  require(first_consumer && second_consumer,
          "mouse-grab frame consumers failed");

  const auto render_pixels = [&](surface::SurfaceKey key,
                                 surface::FrameConsumer &consumer,
                                 const Mapping &mapping) {
    runtime.request_render();
    for (int attempt = 0; attempt < 4; ++attempt) {
      const auto frame = runtime.render();
      require(frame.has_value(), "mouse-grab surface did not render");
      if (frame->ready.surface != key)
        continue;
      require(consumer.consume(mapping.bytes(), frame->ready) ==
                  surface::ConsumeResult::accepted,
              "mouse-grab frame was not consumable");
      return std::vector<std::byte>(consumer.last_frame()->pixels);
    }
    throw std::runtime_error("mouse-grab surface was not scheduled");
  };
  const auto first_baseline =
      render_pixels(first->surface, *first_consumer, first_mapping);
  auto second_pixels =
      render_pixels(second->surface, *second_consumer, second_mapping);

  InputEventProbe probe;
  QCoreApplication::instance()->installEventFilter(&probe);
  std::uint64_t sequence = 1;
  const auto accepted = [&](surface::SurfaceKey key,
                            surface::InputPayload payload) {
    const bool result = static_cast<bool>(runtime.input(
        {.surface = key,
         .sequence = sequence,
         .payload = std::move(payload)}));
    ++sequence;
    return result;
  };
  const surface::PointerButton press{
      .position = {.x_q16 = 10U << 16, .y_q16 = 10U << 16},
      .button = static_cast<std::uint32_t>(Qt::LeftButton),
      .state = surface::ButtonState::pressed,
      .buttons = static_cast<std::uint32_t>(Qt::LeftButton)};
  auto release = press;
  release.state = surface::ButtonState::released;
  release.buttons = 0;
  const surface::PointerMotion motion{
      .position = {.x_q16 = 11U << 16, .y_q16 = 11U << 16},
      .buttons = static_cast<std::uint32_t>(Qt::LeftButton)};
  const auto exercise_second = [&] {
    require(accepted(second->surface,
                     surface::FocusChanged{.focused = true}) &&
                accepted(second->surface, press) &&
                accepted(second->surface, motion) &&
                accepted(second->surface, release) &&
                accepted(second->surface,
                         surface::FocusChanged{.focused = false}),
            "second surface did not accept mouse interaction");
    const auto changed =
        render_pixels(second->surface, *second_consumer, second_mapping);
    require(changed != second_pixels,
            "second-surface input was retained by the old child grabber");
    second_pixels = changed;
  };

  require(accepted(first->surface,
                   surface::FocusChanged{.focused = true}) &&
              accepted(first->surface, press),
          "expressive child MouseArea press was rejected");
  require(render_pixels(first->surface, *first_consumer, first_mapping) !=
              first_baseline,
          "expressive child MouseArea did not receive the press");
  const auto prior_touch_cancels = probe.touch_cancel_count;
  require(accepted(first->surface,
                   surface::FocusChanged{.focused = false}) &&
              probe.touch_cancel_count == prior_touch_cancels,
          "focus loss retained child mouse grab or emitted spurious touch cancel");
  const auto after_focus_loss =
      render_pixels(first->surface, *first_consumer, first_mapping);
  exercise_second();
  const auto first_after_second =
      render_pixels(first->surface, *first_consumer, first_mapping);
  if (first_after_second != after_focus_loss) {
    throw std::runtime_error(
        "old child changed after focus loss: before=" +
        std::to_string(std::to_integer<unsigned char>(after_focus_loss[0])) +
        "," +
        std::to_string(std::to_integer<unsigned char>(after_focus_loss[1])) +
        "," +
        std::to_string(std::to_integer<unsigned char>(after_focus_loss[2])) +
        " after=" +
        std::to_string(std::to_integer<unsigned char>(first_after_second[0])) +
        "," +
        std::to_string(std::to_integer<unsigned char>(first_after_second[1])) +
        "," +
        std::to_string(std::to_integer<unsigned char>(first_after_second[2])));
  }

  require(accepted(first->surface,
                   surface::FocusChanged{.focused = true}) &&
              accepted(first->surface, press),
          "child MouseArea did not reacquire its grab before cancel");
  require(accepted(first->surface, surface::Cancel{}) &&
              probe.touch_cancel_count == prior_touch_cancels,
          "cancel retained child mouse grab or emitted spurious touch cancel");
  const auto after_cancel =
      render_pixels(first->surface, *first_consumer, first_mapping);
  exercise_second();
  require(render_pixels(first->surface, *first_consumer, first_mapping) ==
              after_cancel,
          "second-surface input reached child after cancel");

  require(accepted(first->surface,
                   surface::FocusChanged{.focused = true}) &&
              accepted(first->surface, press),
          "child MouseArea did not reacquire its grab before suspend");
  require(static_cast<bool>(runtime.suspend(first->surface)) &&
              probe.touch_cancel_count == prior_touch_cancels &&
              static_cast<bool>(runtime.resume(first->surface)),
          "suspend retained child mouse grab or emitted spurious touch cancel");
  const auto after_suspend =
      render_pixels(first->surface, *first_consumer, first_mapping);
  require(static_cast<bool>(runtime.suspend(first->surface)),
          "clean first surface did not resuspend");
  exercise_second();
  require(static_cast<bool>(runtime.resume(first->surface)) &&
              render_pixels(first->surface, *first_consumer, first_mapping) ==
                  after_suspend,
          "second-surface input reached child after suspend");

  require(accepted(first->surface,
                   surface::FocusChanged{.focused = true}) &&
              accepted(first->surface, press),
          "child MouseArea did not reacquire its grab before release");
  require(static_cast<bool>(runtime.release(first->surface)) &&
              probe.touch_cancel_count == prior_touch_cancels,
          "surface release retained child mouse grab or emitted touch cancel");
  exercise_second();
  require(static_cast<bool>(runtime.release(second->surface)),
          "second mouse-grab surface did not tear down cleanly");
  QCoreApplication::instance()->removeEventFilter(&probe);
}

void two_surface_activation() {
  worker::WorkerRuntime runtime(fixture("multi-surface"));
  const auto loaded_bar = runtime.load_surface_entry("bar", "Bar.qml");
  if (!loaded_bar)
    throw std::runtime_error("bar QML did not load: " + loaded_bar.detail);
  const auto loaded_atlas =
      runtime.load_surface_entry("atlas", "Atlas.qml");
  if (!loaded_atlas)
    throw std::runtime_error("atlas QML did not load: " +
                             loaded_atlas.detail);
  require(runtime.object_count() >= 2,
          "two declared QML roots did not share one runtime");
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "multi-surface software profile was not selected");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "multi-surface page size unavailable");
  const auto bar = surface::make_allocation(
      {.id = 51, .generation = 12}, 72, 48, 72, 48, 1, 1,
      static_cast<std::uint64_t>(page_size));
  const auto atlas = surface::make_allocation(
      {.id = 52, .generation = 12}, 320, 200, 320, 200, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(bar && atlas &&
              static_cast<bool>(runtime.bind_surface("bar", bar->surface)) &&
              static_cast<bool>(
                  runtime.bind_surface("atlas", atlas->surface)),
          "declared roots did not bind distinct host surface identities");
  require(runtime.surface_key("bar") == bar->surface &&
              runtime.surface_key("atlas") == atlas->surface &&
              !runtime.surface_key("missing"),
          "declared surface names did not resolve only to host bindings");

  const int bar_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-bar-frame", MFD_CLOEXEC));
  const int atlas_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-atlas-frame", MFD_CLOEXEC));
  require(bar_fd >= 0 && atlas_fd >= 0 &&
              ftruncate(bar_fd, static_cast<off_t>(bar->mapping_bytes)) == 0 &&
              ftruncate(atlas_fd, static_cast<off_t>(atlas->mapping_bytes)) ==
                  0,
          "multi-surface frame mappings failed");
  Mapping bar_mapping(bar_fd, static_cast<std::size_t>(bar->mapping_bytes));
  Mapping atlas_mapping(atlas_fd,
                        static_cast<std::size_t>(atlas->mapping_bytes));
  const int bar_worker_fd = fcntl(bar_fd, F_DUPFD_CLOEXEC, 64);
  const int atlas_worker_fd = fcntl(atlas_fd, F_DUPFD_CLOEXEC, 64);
  close(bar_fd);
  close(atlas_fd);
  require(bar_worker_fd >= 0 && atlas_worker_fd >= 0 &&
              static_cast<bool>(runtime.allocate(*bar, bar_worker_fd)) &&
              static_cast<bool>(runtime.allocate(*atlas, atlas_worker_fd)),
          "two surface allocations were not admitted independently");

  const auto first = runtime.render();
  const auto second = runtime.render();
  require(first && second && first->ready.surface == bar->surface &&
              second->ready.surface == atlas->surface,
          "round-robin frames lost per-surface identity");
  auto bar_consumer = surface::FrameConsumer::create(*bar);
  auto atlas_consumer = surface::FrameConsumer::create(*atlas);
  require(bar_consumer && atlas_consumer &&
              bar_consumer->consume(bar_mapping.bytes(), first->ready) ==
                  surface::ConsumeResult::accepted &&
              atlas_consumer->consume(atlas_mapping.bytes(), second->ready) ==
                  surface::ConsumeResult::accepted &&
              bar_consumer->last_frame()->pixels !=
                  atlas_consumer->last_frame()->pixels,
          "distinct QML roots did not publish distinct trusted frames");
  const auto bar_before_intent = bar_consumer->last_frame()->pixels;
  const auto atlas_before_intent = atlas_consumer->last_frame()->pixels;
  require(!runtime.can_deliver_surface_intent("bar") &&
              runtime.can_deliver_surface_intent("atlas") &&
              !runtime.can_deliver_surface_intent("missing") &&
              !runtime.deliver_surface_intent("bar", {}) &&
              runtime.deliver_surface_intent(
                  "atlas", {{QStringLiteral("color"),
                              QStringLiteral("#24733f")}}),
          "intent data did not target only the declared receiving root");
  const auto intent_frame = runtime.render();
  require(intent_frame && intent_frame->ready.surface == atlas->surface &&
              atlas_consumer->consume(atlas_mapping.bytes(),
                                      intent_frame->ready) ==
                  surface::ConsumeResult::accepted &&
              atlas_consumer->last_frame()->pixels != atlas_before_intent &&
              bar_consumer->last_frame()->pixels == bar_before_intent,
          "target-only intent data did not repaint only its receiving surface");

  require(static_cast<bool>(runtime.input(
              {.surface = bar->surface,
               .sequence = 1,
               .payload = surface::FocusChanged{.focused = true}})) &&
              !static_cast<bool>(runtime.input(
                  {.surface = atlas->surface,
                   .sequence = 2,
                   .payload = surface::FocusChanged{.focused = true}})) &&
              static_cast<bool>(runtime.input(
                  {.surface = bar->surface,
                   .sequence = 2,
                   .payload = surface::FocusChanged{.focused = false}})) &&
              static_cast<bool>(runtime.input(
                  {.surface = atlas->surface,
                   .sequence = 3,
                   .payload = surface::FocusChanged{.focused = true}})),
          "runtime-wide focus and sequence authority was not exact");
  require(static_cast<bool>(runtime.release(bar->surface)) &&
              runtime.active() &&
              !static_cast<bool>(runtime.resume(bar->surface)) &&
              runtime.surface_key("bar") == bar->surface,
          "one surface teardown damaged its sibling or trusted binding");
  runtime.request_render();
  const auto survivor = runtime.render();
  require(survivor && survivor->ready.surface == atlas->surface,
          "surviving surface did not render independently");

  const auto stale_bar = surface::make_allocation(
      {.id = bar->surface.id, .generation = bar->surface.generation + 1}, 72, 48,
      72, 48, 1, 1, static_cast<std::uint64_t>(page_size));
  const int stale_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-stale-reattach", MFD_CLOEXEC));
  require(stale_bar && stale_fd >= 0 &&
              ftruncate(stale_fd,
                        static_cast<off_t>(stale_bar->mapping_bytes)) == 0 &&
              !static_cast<bool>(runtime.allocate(*stale_bar, stale_fd)),
          "replacement attachment crossed its trusted generation binding");
  errno = 0;
  require(fcntl(stale_fd, F_GETFD) == -1 && errno == EBADF,
          "rejected replacement descriptor remained open");

  const int replacement_fd = static_cast<int>(
      syscall(SYS_memfd_create, "worker-bar-reattach", MFD_CLOEXEC));
  require(replacement_fd >= 0 &&
              ftruncate(replacement_fd,
                        static_cast<off_t>(bar->mapping_bytes)) == 0,
          "replacement frame mapping failed");
  Mapping replacement_mapping(
      replacement_fd, static_cast<std::size_t>(bar->mapping_bytes));
  const int replacement_worker_fd =
      fcntl(replacement_fd, F_DUPFD_CLOEXEC, 64);
  close(replacement_fd);
  require(replacement_worker_fd >= 0 &&
              static_cast<bool>(runtime.allocate(*bar, replacement_worker_fd)),
          "exact released surface did not reallocate in the live worker");
  const auto replacement = runtime.render();
  auto replacement_consumer = surface::FrameConsumer::create(*bar);
  require(replacement && replacement->ready.surface == bar->surface &&
              replacement_consumer &&
              replacement_consumer->consume(replacement_mapping.bytes(),
                                            replacement->ready) ==
                  surface::ConsumeResult::accepted,
          "reattached surface did not publish a consumable frame");
  require(static_cast<bool>(runtime.release(atlas->surface)) &&
              static_cast<bool>(runtime.release(bar->surface)) &&
              !runtime.allocated() &&
              runtime.surface_key("bar") == bar->surface &&
              runtime.surface_key("atlas") == atlas->surface,
          "reattached surfaces did not tear down with exact bindings intact");
}

void device_pixel_ratio_scales_scene_pixels() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(runtime.load_manifest_entry()) &&
              static_cast<bool>(runtime.select_software_profile(
                  surface::software_profile_offer())),
          "DPR scene did not load");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "page size unavailable for DPR scene");
  const auto allocation =
      surface::make_allocation({.id = 42, .generation = 10}, 64, 32, 128, 64, 2,
                               1, static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "DPR allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "worker-dpr-test", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "DPR memfd failed");
  Mapping mapping(descriptor,
                  static_cast<std::size_t>(allocation->mapping_bytes));
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 && static_cast<bool>(runtime.allocate(
                                        *allocation, worker_descriptor)),
          "DPR allocation was rejected");
  const auto published = runtime.render();
  auto consumer = surface::FrameConsumer::create(*allocation);
  require(published.has_value() && consumer.has_value() &&
              consumer->consume(mapping.bytes(), published->ready) ==
                  surface::ConsumeResult::accepted,
          "DPR frame was not consumable");
  const auto *frame = consumer->last_frame();
  constexpr std::size_t sample_x = 100;
  constexpr std::size_t sample_y = 50;
  const auto alpha_offset = sample_y * allocation->stride + sample_x * 4 + 3;
  require(frame != nullptr && alpha_offset < frame->pixels.size() &&
              frame->pixels[alpha_offset] != std::byte{0},
          "DPR 2 scene occupied only the logical-size corner of its buffer");
}

void asynchronous_scene_change_publishes_distinct_frame() {
  worker::WorkerRuntime runtime(fixture("async-change"));
  require(static_cast<bool>(runtime.load_manifest_entry()) &&
              static_cast<bool>(runtime.select_software_profile(
                  surface::software_profile_offer())),
          "async scene did not load");
  const auto page_size = sysconf(_SC_PAGESIZE);
  require(page_size > 0, "page size unavailable for async scene");
  const auto allocation = surface::make_allocation(
      {.id = 43, .generation = 11}, 64, 32, 64, 32, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(allocation.has_value(), "async allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "worker-async-test", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "async memfd failed");
  Mapping mapping(descriptor,
                  static_cast<std::size_t>(allocation->mapping_bytes));
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 && static_cast<bool>(runtime.allocate(
                                        *allocation, worker_descriptor)),
          "async allocation was rejected");
  auto consumer = surface::FrameConsumer::create(*allocation);
  const auto first = runtime.render();
  require(first.has_value() && consumer.has_value() &&
              consumer->consume(mapping.bytes(), first->ready) ==
                  surface::ConsumeResult::accepted,
          "async initial frame was not consumable");
  const QImage first_image(
      reinterpret_cast<const uchar *>(consumer->last_frame()->pixels.data()),
      static_cast<int>(allocation->pixel_width),
      static_cast<int>(allocation->pixel_height),
      static_cast<int>(allocation->stride),
      QImage::Format_RGBA8888_Premultiplied);
  const QImage first_copy = first_image.copy();
  require(!runtime.render().has_value(),
          "clean async scene was redundantly republished");
  QEventLoop loop;
  QTimer::singleShot(60, &loop, &QEventLoop::quit);
  loop.exec();
  require(runtime.render_requested(),
          "async QML property change did not dirty render control");
  const auto second = runtime.render();
  require(second.has_value() && second->ready.frame_sequence == 2 &&
              consumer->consume(mapping.bytes(), second->ready) ==
                  surface::ConsumeResult::accepted,
          "async changed frame was not consumable");
  const QImage second_image(
      reinterpret_cast<const uchar *>(consumer->last_frame()->pixels.data()),
      static_cast<int>(allocation->pixel_width),
      static_cast<int>(allocation->pixel_height),
      static_cast<int>(allocation->stride),
      QImage::Format_RGBA8888_Premultiplied);
  require(second_image != first_copy,
          "async QML property change republished stale pixels");
}

void hostile_loading() {
  require(!worker::safe_relative_qml_path("../Main.qml") &&
              !worker::safe_relative_qml_path("/plugin/Main.qml") &&
              !worker::safe_relative_qml_path("Main.js") &&
              worker::safe_relative_qml_path("ui/Main.qml"),
          "entry path policy is not closed");
  worker::WorkerRuntime window(fixture("window"));
  const auto window_result = window.load_entry("Window.qml");
  require(!window_result &&
              window_result.failure == worker::RuntimeFailure::root_not_item,
          "plugin-created non-item root crossed host surface ownership");

  ExactQmlTree exact_qml;
  worker::WorkerRuntime remote(fixture("remote"), exact_qml.root());
  require(static_cast<bool>(remote.prepare_trusted_qt_types()) &&
              !static_cast<bool>(remote.load_entry("Remote.qml")),
          "remote QML URL crossed the runtime import boundary");

  worker::WorkerRuntime unknown(fixture("unknown-module"), exact_qml.root());
  require(static_cast<bool>(unknown.prepare_trusted_qt_types()) &&
              !static_cast<bool>(unknown.load_manifest_entry()),
          "uncertified QtQuick.Dialogs loaded from the synthetic tree");

  worker::WorkerRuntime controls_shadow(fixture("controls-shadow"),
                                         exact_qml.root());
  require(static_cast<bool>(controls_shadow.prepare_trusted_qt_types()) &&
              static_cast<bool>(controls_shadow.load_manifest_entry()) &&
              controls_shadow.root_object_name() == "trusted",
          "plugin-local module shadowed certified QtQuick.Controls");

  worker::WorkerRuntime host_shell(fixture("host-shell-module"),
                                   exact_qml.root());
  require(static_cast<bool>(host_shell.prepare_trusted_qt_types()) &&
              !static_cast<bool>(host_shell.load_manifest_entry()),
          "trusted shell qs.Commons module crossed the worker boundary");

  const auto quickshell_root =
      std::filesystem::temp_directory_path() /
      ("omarchy-worker-quickshell-module-" +
       std::to_string(static_cast<long long>(getpid())));
  std::filesystem::create_directory(quickshell_root);
  std::ofstream(quickshell_root / "Main.qml")
      << "import QtQuick\nimport Quickshell\nItem {}\n";
  std::ofstream(quickshell_root / "manifest.json")
      << R"({"schemaVersion":2,"id":"example.quickshell-module","name":"Quickshell module fixture","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"main":{"role":"panel"}},"permissions":{"required":[],"optional":[]}})";
  worker::WorkerRuntime quickshell(quickshell_root, exact_qml.root());
  require(static_cast<bool>(quickshell.prepare_trusted_qt_types()) &&
              !static_cast<bool>(quickshell.load_manifest_entry()),
          "ambient Quickshell module crossed the worker boundary");
  std::filesystem::remove_all(quickshell_root);

  const auto native_surface_root =
      std::filesystem::temp_directory_path() /
      ("omarchy-worker-native-surface-" +
       std::to_string(static_cast<long long>(getpid())));
  std::filesystem::create_directory(native_surface_root);
  const auto write_native_surface_fixture =
      [&](std::string_view id, std::string_view source) {
        std::ofstream(native_surface_root / "Main.qml") << source;
        std::ofstream(native_surface_root / "manifest.json")
            << R"({"schemaVersion":2,"id":")" << id
            << R"(","name":"Native surface fixture","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"main":{"role":"panel"}},"permissions":{"required":[],"optional":[]}})";
      };
  const auto windows_before = QGuiApplication::topLevelWindows().size();
  write_native_surface_fixture(
      "example.quickshell-wayland",
      "import QtQuick\nimport Quickshell.Wayland\nItem {}\n");
  worker::WorkerRuntime wayland(native_surface_root, exact_qml.root());
  require(static_cast<bool>(wayland.prepare_trusted_qt_types()) &&
              !static_cast<bool>(wayland.load_manifest_entry()) &&
              QGuiApplication::topLevelWindows().size() == windows_before,
          "Quickshell.Wayland created or exposed a native surface");

  write_native_surface_fixture(
      "example.qt-window",
      "import QtQuick\nimport QtQuick.Window\nItem { Window { visible: true } }\n");
  worker::WorkerRuntime qt_window(native_surface_root, exact_qml.root());
  require(static_cast<bool>(qt_window.prepare_trusted_qt_types()) &&
              !static_cast<bool>(qt_window.load_manifest_entry()) &&
              QGuiApplication::topLevelWindows().size() == windows_before,
          "QtQuick.Window created or exposed a plugin-owned top level");
  std::filesystem::remove_all(native_surface_root);

  worker::WorkerRuntime presentation(fixture("presentation"),
                                     exact_qml.root());
  require(static_cast<bool>(presentation.prepare_trusted_qt_types()) &&
              static_cast<bool>(presentation.load_manifest_entry()) &&
              presentation.root_object_name() == "presentation-loaded",
          "worker-owned presentation SDK did not load");

  worker::WorkerRuntime shadowed_presentation(fixture("presentation-shadow"),
                                              exact_qml.root());
  require(static_cast<bool>(shadowed_presentation.prepare_trusted_qt_types()) &&
              static_cast<bool>(shadowed_presentation.load_manifest_entry()) &&
              shadowed_presentation.root_object_name() ==
                  "trusted-presentation",
          "plugin-local module shadowed the worker presentation SDK");

  worker::WorkerRuntime quickshell_io(fixture("quickshell-io"),
                                      exact_qml.root());
  require(static_cast<bool>(quickshell_io.prepare_trusted_qt_types()) &&
              static_cast<bool>(quickshell_io.load_manifest_entry()) &&
              quickshell_io.root_object_name() == "quickshell-io-loaded",
          "worker-owned Quickshell.Io compatibility module did not load");

  worker::WorkerRuntime shadowed_quickshell_io(fixture("quickshell-io-shadow"),
                                               exact_qml.root());
  require(static_cast<bool>(shadowed_quickshell_io.prepare_trusted_qt_types()) &&
              static_cast<bool>(shadowed_quickshell_io.load_manifest_entry()) &&
              shadowed_quickshell_io.root_object_name() ==
                  "trusted-quickshell-io",
          "plugin-local module shadowed worker Quickshell.Io compatibility");

  worker::WorkerRuntime quickshell_io_process(fixture("quickshell-io-process"),
                                              exact_qml.root());
  require(static_cast<bool>(
              quickshell_io_process.prepare_trusted_qt_types()) &&
              !static_cast<bool>(quickshell_io_process.load_manifest_entry()),
          "Quickshell.Io compatibility exposed ambient Process execution");

  worker::WorkerRuntime local_module(fixture("local-module"));
  require(static_cast<bool>(local_module.prepare_trusted_qt_types()) &&
              static_cast<bool>(local_module.load_manifest_entry()),
          "plugin-local pure-QML URI module was rejected");

  worker::WorkerRuntime local_native(fixture("local-native"));
  const auto local_native_result = local_native.prepare_trusted_qt_types();
  require(!local_native_result &&
              local_native_result.detail.find("pure QML") != std::string::npos,
          "BOM/tab plugin-local native module directive was accepted");

  worker::WorkerRuntime local_redirect(fixture("local-redirect"));
  const auto local_redirect_result = local_redirect.prepare_trusted_qt_types();
  require(!local_redirect_result &&
              local_redirect_result.detail.find("pure QML") !=
                  std::string::npos,
          "BOM/tab plugin-local redirect directive was accepted");

  worker::WorkerRuntime bomb(fixture("object-bomb"));
  const auto bomb_result = bomb.load_entry("Bomb.qml");
  require(!bomb_result &&
              bomb_result.failure == worker::RuntimeFailure::object_limit,
          "oversized object tree bypassed the worker bound");

  const auto temporary = std::filesystem::temp_directory_path() /
                         ("omarchy-worker-symlink-" +
                          std::to_string(static_cast<long long>(getpid())));
  std::filesystem::create_directory(temporary);
  std::filesystem::create_symlink("/etc/passwd", temporary / "escape.qml");
  worker::WorkerRuntime symlinked(temporary);
  const auto result = symlinked.load_entry("escape.qml");
  std::filesystem::remove_all(temporary);
  require(!result &&
              result.failure == worker::RuntimeFailure::invalid_source_root,
          "symlinked plugin resource was followed");
}

void bounded_image_decoding() {
  QByteArray encoded;
  {
    QImage source(4097, 4097, QImage::Format_RGBA8888);
    require(!source.isNull(), "compressed image fixture allocation failed");
    source.fill(Qt::transparent);
    QBuffer output(&encoded);
    require(output.open(QIODevice::WriteOnly) && source.save(&output, "PNG"),
            "compressed image fixture encoding failed");
  }
  require(encoded.size() < 1024 * 1024,
          "compressed image fixture is not a bounded bomb");

  worker::WorkerRuntime runtime(fixture("expressive"));
  require(QImageReader::allocationLimit() == worker::kMaximumDecodedImageMiB,
          "worker did not install the decoded-image allocation ceiling");

  QBuffer oversized_input(&encoded);
  require(oversized_input.open(QIODevice::ReadOnly),
          "oversized image buffer did not open");
  QImageReader oversized(&oversized_input, "PNG");
  require(oversized.size() == QSize(4097, 4097) && oversized.read().isNull(),
          "compressed image exceeded the worker allocation ceiling");

  QImage small_source(32, 32, QImage::Format_RGBA8888);
  small_source.fill(Qt::green);
  QByteArray small_encoded;
  QBuffer small_output(&small_encoded);
  require(small_output.open(QIODevice::WriteOnly) &&
              small_source.save(&small_output, "PNG"),
          "small image fixture encoding failed");
  QBuffer small_input(&small_encoded);
  require(small_input.open(QIODevice::ReadOnly),
          "small image buffer did not open");
  QImageReader small(&small_input, "PNG");
  const auto decoded = small.read();
  require(!decoded.isNull() && decoded.size() == QSize(32, 32),
          "decoded-image ceiling disabled ordinary plugin images");

  const QByteArray truncated = small_encoded.first(small_encoded.size() / 3);
  const QByteArray malformed("not-an-image\0\xff", 14);
  for (int attempt = 0; attempt < 32; ++attempt) {
    for (const auto &bytes : {truncated, malformed}) {
      QBuffer input;
      input.setData(bytes);
      require(input.open(QIODevice::ReadOnly),
              "hostile image buffer did not open");
      QImageReader reader(&input);
      require(reader.read().isNull(),
              "malformed or unsupported image decoded successfully");
    }
  }
}

void steady_state_denies_exec() {
  const pid_t child = fork();
  require(child >= 0, "seccomp test fork failed");
  if (child == 0) {
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(10);
    char executable[] = "/bin/true";
    char *arguments[] = {executable, nullptr};
    char *environment[] = {nullptr};
    errno = 0;
    execve(executable, arguments, environment);
    _exit(errno == EPERM ? 0 : 11);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "steady-state filter did not deny execve with EPERM");
}

void trusted_shapes_load_after_steady_state() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "trusted Shapes seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("trusted-shapes"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    if (!prepared)
      _exit(20);
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(21);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded)
      static_cast<void>(write(STDERR_FILENO, loaded.detail.data(),
                              loaded.detail.size()));
    _exit(loaded && runtime.loaded() && runtime.root_object_name().empty()
              ? 0
              : 22);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "certified system QtQuick.Shapes did not defeat plugin shadowing");
}

void trusted_layouts_load_after_steady_state() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "trusted Layouts seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("trusted-layouts"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    if (!prepared)
      _exit(23);
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(24);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded)
      static_cast<void>(write(STDERR_FILENO, loaded.detail.data(),
                              loaded.detail.size()));
    _exit(loaded && runtime.loaded() &&
                  runtime.root_object_name() == "trusted-layouts"
              ? 0
              : 25);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "certified system QtQuick.Layouts did not defeat plugin shadowing");
}

void trusted_effects_load_after_steady_state() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "trusted Effects seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("trusted-effects"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    if (!prepared)
      _exit(26);
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(27);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded)
      static_cast<void>(write(STDERR_FILENO, loaded.detail.data(),
                              loaded.detail.size()));
    _exit(loaded && runtime.loaded() &&
                  runtime.root_object_name() == "trusted-effects"
              ? 0
              : 28);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "certified system QtQuick.Effects did not defeat plugin shadowing");
}

void trusted_controls_load_after_steady_state() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "trusted Controls seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("trusted-controls"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    if (!prepared)
      _exit(46);
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(47);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded)
      static_cast<void>(write(STDERR_FILENO, loaded.detail.data(),
                              loaded.detail.size()));
    _exit(loaded && runtime.loaded() &&
                  runtime.root_object_name() == "basic-controls-1"
              ? 0
              : 48);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "certified QtQuick.Controls did not load after steady-state seccomp");
}

void trusted_quickshell_io_loads_after_steady_state() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "trusted Quickshell.Io seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("quickshell-io"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    std::string error;
    if (!prepared || !worker::install_steady_state_seccomp(error))
      _exit(51);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded)
      static_cast<void>(write(STDERR_FILENO, loaded.detail.data(),
                              loaded.detail.size()));
    _exit(loaded && runtime.loaded() &&
                  runtime.root_object_name() == "quickshell-io-loaded"
              ? 0
              : 52);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "Quickshell.Io compatibility did not load after steady-state seccomp");
}

void dynamic_module_resolution_stays_certified() {
  const pid_t unrestricted = fork();
  require(unrestricted >= 0, "dynamic module positive-control fork failed");
  if (unrestricted == 0) {
    QQmlEngine engine;
    QQmlComponent component(&engine,
                            QUrl::fromLocalFile(QString::fromStdString(
                                (fixture("dynamic-module") / "Main.qml")
                                    .string())));
    std::unique_ptr<QObject> root(component.create());
    _exit(root && root->objectName() == QStringLiteral("dialog-loaded") ? 0
                                                                         : 29);
  }
  int unrestricted_status = 0;
  require(waitpid(unrestricted, &unrestricted_status, 0) == unrestricted &&
              WIFEXITED(unrestricted_status) &&
              WEXITSTATUS(unrestricted_status) == 0,
          "dynamic Dialogs adversary lacks a working positive control");

  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "dynamic module seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("dynamic-module"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    if (!prepared)
      _exit(30);
    std::string error;
    if (!worker::install_steady_state_seccomp(error))
      _exit(31);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded || !runtime.root_object_name().empty()) {
      const auto detail = std::string("dynamic count=") +
                          std::to_string(runtime.object_count()) + " " +
                          loaded.detail + "\n";
      static_cast<void>(write(STDERR_FILENO, detail.data(), detail.size()));
    }
    _exit(loaded && runtime.root_object_name().empty() ? 0 : 32);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "runtime-created QML resolved an uncertified native module");
}

void dynamic_certified_shapes_succeeds() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "dynamic Shapes seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("dynamic-shapes"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    std::string error;
    if (!prepared || !worker::install_steady_state_seccomp(error))
      _exit(40);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded || runtime.root_object_name() != "shapes-loaded") {
      const auto detail = std::string("dynamic Shapes marker=") +
                          runtime.root_object_name() + " objects=" +
                          std::to_string(runtime.object_count()) + " " +
                          loaded.detail + "\n";
      static_cast<void>(write(STDERR_FILENO, detail.data(), detail.size()));
    }
    _exit(loaded && runtime.root_object_name() == "shapes-loaded" ? 0 : 41);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "runtime-created certified QtQuick.Shapes module failed");
}

void dynamic_certified_layouts_succeeds() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "dynamic Layouts seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("dynamic-layouts"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    std::string error;
    if (!prepared || !worker::install_steady_state_seccomp(error))
      _exit(42);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded || runtime.root_object_name() != "layouts-loaded") {
      const auto detail = std::string("dynamic Layouts marker=") +
                          runtime.root_object_name() + " objects=" +
                          std::to_string(runtime.object_count()) + " " +
                          loaded.detail + "\n";
      static_cast<void>(write(STDERR_FILENO, detail.data(), detail.size()));
    }
    _exit(loaded && runtime.root_object_name() == "layouts-loaded" ? 0 : 43);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "runtime-created certified QtQuick.Layouts module failed");
}

void dynamic_certified_effects_succeeds() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "dynamic Effects seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("dynamic-effects"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    std::string error;
    if (!prepared || !worker::install_steady_state_seccomp(error))
      _exit(44);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded || runtime.root_object_name() != "effects-loaded") {
      const auto detail = std::string("dynamic Effects marker=") +
                          runtime.root_object_name() + " objects=" +
                          std::to_string(runtime.object_count()) + " " +
                          loaded.detail + "\n";
      static_cast<void>(write(STDERR_FILENO, detail.data(), detail.size()));
    }
    _exit(loaded && runtime.root_object_name() == "effects-loaded" ? 0 : 45);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "runtime-created certified QtQuick.Effects module failed");
}

void dynamic_certified_controls_succeeds() {
  ExactQmlTree qml_tree;
  const pid_t child = fork();
  require(child >= 0, "dynamic Controls seccomp test fork failed");
  if (child == 0) {
    worker::WorkerRuntime runtime(fixture("dynamic-controls"), qml_tree.root());
    const auto prepared = runtime.prepare_trusted_qt_types();
    std::string error;
    if (!prepared || !worker::install_steady_state_seccomp(error))
      _exit(49);
    const auto loaded = runtime.load_manifest_entry();
    if (!loaded || runtime.root_object_name() != "dynamic-loaded") {
      const auto detail = std::string("dynamic Controls marker=") +
                          runtime.root_object_name() + " objects=" +
                          std::to_string(runtime.object_count()) + " " +
                          loaded.detail + "\n";
      static_cast<void>(write(STDERR_FILENO, detail.data(), detail.size()));
    }
    _exit(loaded && runtime.root_object_name() == "dynamic-loaded" ? 0 : 50);
  }
  int status = 0;
  require(waitpid(child, &status, 0) == child && WIFEXITED(status) &&
              WEXITSTATUS(status) == 0,
          "runtime-created certified QtQuick.Controls module failed");
}

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    if (argc == 2 && std::string_view(argv[1]) == "--headless-only") {
      headless_entry_has_no_surface_authority();
      std::cout << "plugin worker headless boundary: ok\n";
      return 0;
    }
    if (argc == 2 &&
        std::string_view(argv[1]) == "--sibling-focus-only") {
      sibling_render_preserves_interaction(SiblingInteraction::focused_text);
      std::cout << "plugin worker sibling focus: ok\n";
      return 0;
    }
    if (argc == 2 &&
        std::string_view(argv[1]) == "--sibling-grab-only") {
      sibling_render_preserves_interaction(SiblingInteraction::pointer_grab);
      std::cout << "plugin worker sibling grab: ok\n";
      return 0;
    }
    render_and_input();
    headless_entry_has_no_surface_authority();
    typed_input_projects_exact_qt_events();
    touch_injector_maps_native_global_coordinates();
    touch_input_reaches_qml_handlers();
    mouse_grab_cleanup_is_surface_scoped();
    two_surface_activation();
    device_pixel_ratio_scales_scene_pixels();
    asynchronous_scene_change_publishes_distinct_frame();
    hostile_loading();
    bounded_image_decoding();
    steady_state_denies_exec();
    trusted_shapes_load_after_steady_state();
    trusted_layouts_load_after_steady_state();
    trusted_effects_load_after_steady_state();
    trusted_controls_load_after_steady_state();
    trusted_quickshell_io_loads_after_steady_state();
    dynamic_module_resolution_stays_certified();
    dynamic_certified_shapes_succeeds();
    dynamic_certified_layouts_succeeds();
    dynamic_certified_effects_succeeds();
    dynamic_certified_controls_succeeds();
    std::cout << "plugin worker runtime: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin worker runtime: " << error.what() << '\n';
    return 1;
  }
}
