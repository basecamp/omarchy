#include "worker_runtime.hpp"

#include <QBuffer>
#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QImageReader>
#include <QTimer>

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
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>

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

void render_and_input() {
  worker::WorkerRuntime runtime(fixture("expressive"));
  require(static_cast<bool>(runtime.prepare_trusted_qt_types()),
          "trusted Qt type preparation failed");
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

  require(
      static_cast<bool>(runtime.focus(
          {.surface = allocation->surface, .sequence = 1, .focused = true})),
      "trusted focus event failed");
  surface::InputEvent press{
      .surface = allocation->surface,
      .sequence = 1,
      .kind = surface::InputKind::pointer_button,
      .x_q16 = 10U << 16,
      .y_q16 = 10U << 16,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = 1,
      .state = static_cast<std::uint32_t>(surface::ButtonState::pressed),
      .active_touch_points = 0,
  };
  require(static_cast<bool>(runtime.input(press)),
          "focused pointer input failed");
  require(!static_cast<bool>(runtime.input(press)),
          "replayed input sequence was accepted");
  auto release = press;
  release.sequence = 2;
  release.state = static_cast<std::uint32_t>(surface::ButtonState::released);
  require(static_cast<bool>(runtime.input(release)),
          "trusted pointer release failed");
  surface::InputEvent touch{
      .surface = allocation->surface,
      .sequence = 3,
      .kind = surface::InputKind::touch,
      .x_q16 = 10U << 16,
      .y_q16 = 10U << 16,
      .delta_x_q16 = 0,
      .delta_y_q16 = 0,
      .code = 1,
      .state = 1,
      .active_touch_points = 1,
  };
  require(static_cast<bool>(runtime.input(touch)),
          "trusted touch begin failed");
  touch.sequence = 4;
  touch.state = 2;
  require(static_cast<bool>(runtime.input(touch)),
          "trusted touch update failed");
  touch.sequence = 5;
  touch.state = 3;
  touch.active_touch_points = 0;
  require(static_cast<bool>(runtime.input(touch)), "trusted touch end failed");
  require(
      static_cast<bool>(runtime.focus(
          {.surface = allocation->surface, .sequence = 2, .focused = false})) &&
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
  require(!runtime.open_surface("atlas", {.id = 52, .generation = 11}),
          "stale surface generation opened a panel");
  require(!runtime.open_surface("bar", bar->surface),
          "surface without presentation lifecycle was opened");
  require(static_cast<bool>(runtime.open_surface("atlas", atlas->surface)),
          "host-managed panel open lifecycle was rejected");

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

  require(static_cast<bool>(runtime.focus(
              {.surface = bar->surface, .sequence = 1, .focused = true})) &&
              static_cast<bool>(runtime.focus(
                  {.surface = atlas->surface,
                   .sequence = 1,
                   .focused = true})),
          "surface focus gates were not independent");
  require(static_cast<bool>(runtime.release(bar->surface)) &&
              runtime.active() &&
              !static_cast<bool>(runtime.resume(bar->surface)),
          "one surface teardown damaged or revived another surface");
  runtime.request_render();
  const auto survivor = runtime.render();
  require(survivor && survivor->ready.surface == atlas->surface &&
              static_cast<bool>(runtime.release(atlas->surface)) &&
              !runtime.allocated(),
          "surviving surface did not render and tear down independently");
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
          "plugin-created top-level Window crossed host surface ownership");

  worker::WorkerRuntime remote(fixture("remote"));
  require(!static_cast<bool>(remote.load_entry("Remote.qml")),
          "remote QML import bypassed the URL policy");

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

} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    render_and_input();
    two_surface_activation();
    device_pixel_ratio_scales_scene_pixels();
    asynchronous_scene_change_publishes_distinct_frame();
    hostile_loading();
    bounded_image_decoding();
    steady_state_denies_exec();
    std::cout << "plugin worker runtime: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin worker runtime: " << error.what() << '\n';
    return 1;
  }
}
