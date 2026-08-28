#include "worker_runtime.hpp"

#include <QEventLoop>
#include <QGuiApplication>
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
    hostile_loading();
    steady_state_denies_exec();
    std::cout << "plugin worker runtime: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin worker runtime: " << error.what() << '\n';
    return 1;
  }
}
