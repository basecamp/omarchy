#include "expressive_surface.hpp"
#include "surface_host.hpp"
#include "worker_runtime.hpp"

#include "manifest_contract.hpp"
#include "omarchy/plugin_runtime/surface/frame_region.hpp"
#include "omarchy/plugin_runtime/surface/frame_transport.hpp"

#include <QEventLoop>
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QTimer>
#include <QVariant>

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <optional>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

namespace expressive = omarchy::plugin_runtime::expressive_surface;
namespace host = omarchy::plugin_runtime::surface_host;
namespace manifest = omarchy::plugins::manifest;
namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;

using Clock = std::chrono::steady_clock;
using Microseconds = std::chrono::microseconds;

const std::filesystem::path kPomodoro{F2_POMODORO_ROOT};
const std::filesystem::path kPet{F2_PET_ROOT};
const std::filesystem::path kArtifacts{F2_ARTIFACT_DIR};

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "fixture could not be read");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

class NullRuntimeApi final : public QObject {
  Q_OBJECT

public:
  Q_INVOKABLE QVariant invoke(const QString &, const QVariantMap &) {
    return false;
  }
};

class Mapping {
public:
  Mapping() = default;
  Mapping(const Mapping &) = delete;
  Mapping &operator=(const Mapping &) = delete;
  ~Mapping() {
    if (address_ != MAP_FAILED)
      munmap(address_, bytes_);
  }

  int create(std::size_t bytes) {
    const int descriptor = static_cast<int>(
        syscall(SYS_memfd_create, "omarchy-f2-frame", MFD_CLOEXEC));
    if (descriptor < 0)
      return -1;
    if (ftruncate(descriptor, static_cast<off_t>(bytes)) != 0) {
      close(descriptor);
      return -1;
    }
    address_ =
        mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (address_ == MAP_FAILED) {
      close(descriptor);
      return -1;
    }
    bytes_ = bytes;
    return descriptor;
  }

  [[nodiscard]] std::span<const std::byte> bytes() const {
    return {static_cast<const std::byte *>(address_), bytes_};
  }

private:
  void *address_ = MAP_FAILED;
  std::size_t bytes_ = 0;
};

struct FrameSample {
  QImage image;
  std::uint64_t render_microseconds = 0;
  std::uint64_t copy_microseconds = 0;
};

class SceneHarness {
public:
  SceneHarness(std::filesystem::path root, std::uint64_t generation,
               std::uint32_t logical_width, std::uint32_t logical_height,
               std::uint32_t dpr, QObject *runtime_api = nullptr)
      : runtime_(std::move(root)) {
    if (runtime_api != nullptr)
      require(static_cast<bool>(runtime_.bind_runtime_api(*runtime_api)),
              "fixed runtime API did not bind");
    require(static_cast<bool>(runtime_.load_manifest_entry()) &&
                static_cast<bool>(runtime_.select_software_profile(
                    surface::software_profile_offer())),
            "arbitrary-QML scene did not load its software profile");
    const auto page_size = sysconf(_SC_PAGESIZE);
    require(page_size > 0, "page size unavailable");
    allocation_ = surface::make_allocation(
        {.id = generation + 1000, .generation = generation}, logical_width,
        logical_height, logical_width * dpr, logical_height * dpr, dpr, 1,
        static_cast<std::uint64_t>(page_size));
    require(allocation_.has_value(), "visual allocation was rejected");
    const int descriptor =
        mapping_.create(static_cast<std::size_t>(allocation_->mapping_bytes));
    const int worker_descriptor =
        descriptor < 0 ? -1 : fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
    if (descriptor >= 0)
      close(descriptor);
    consumer_ = surface::FrameConsumer::create(*allocation_);
    require(worker_descriptor >= 0 && consumer_.has_value() &&
                static_cast<bool>(
                    runtime_.allocate(*allocation_, worker_descriptor)),
            "visual frame mapping was rejected");
  }

  ~SceneHarness() {
    if (runtime_.allocated())
      static_cast<void>(runtime_.release(allocation_->surface));
  }

  FrameSample frame() {
    const auto render_started = Clock::now();
    const auto published = runtime_.render();
    const auto render_finished = Clock::now();
    require(published.has_value(), "software worker did not publish a frame");
    const auto copy_started = Clock::now();
    require(consumer_->consume(mapping_.bytes(), published->ready) ==
                surface::ConsumeResult::accepted,
            "trusted consumer rejected a software frame");
    const auto copy_finished = Clock::now();
    const auto *copied = consumer_->last_frame();
    require(copied != nullptr, "trusted consumer retained no frame");
    const QImage borrowed(
        reinterpret_cast<const uchar *>(copied->pixels.data()),
        static_cast<int>(allocation_->pixel_width),
        static_cast<int>(allocation_->pixel_height),
        static_cast<qsizetype>(allocation_->stride),
        QImage::Format_RGBA8888_Premultiplied);
    QImage owned = borrowed.copy();
    owned.setDevicePixelRatio(static_cast<qreal>(allocation_->dpr_numerator) /
                              allocation_->dpr_denominator);
    require(!owned.isNull(), "trusted image copy failed");
    return {.image = std::move(owned),
            .render_microseconds = static_cast<std::uint64_t>(
                std::chrono::duration_cast<Microseconds>(render_finished -
                                                         render_started)
                    .count()),
            .copy_microseconds = static_cast<std::uint64_t>(
                std::chrono::duration_cast<Microseconds>(copy_finished -
                                                         copy_started)
                    .count())};
  }

  worker::WorkerRuntime &runtime() { return runtime_; }
  const surface::TrustedAllocation &allocation() const { return *allocation_; }

private:
  worker::WorkerRuntime runtime_;
  std::optional<surface::TrustedAllocation> allocation_;
  Mapping mapping_;
  std::optional<surface::FrameConsumer> consumer_;
};

void wait_milliseconds(int milliseconds) {
  QEventLoop loop;
  QTimer::singleShot(milliseconds, &loop, &QEventLoop::quit);
  loop.exec();
}

surface::InputEvent pointer(surface::SurfaceKey key, std::uint64_t sequence,
                            surface::ButtonState state) {
  return {.surface = key,
          .sequence = sequence,
          .kind = surface::InputKind::pointer_button,
          .x_q16 = 36U << surface::kQ16FractionBits,
          .y_q16 = 124U << surface::kQ16FractionBits,
          .delta_x_q16 = 0,
          .delta_y_q16 = 0,
          .code = 1,
          .state = static_cast<std::uint32_t>(state),
          .active_touch_points = 0};
}

QImage checkerboard(const QImage &source) {
  QImage result(source.size(), QImage::Format_RGBA8888_Premultiplied);
  result.setDevicePixelRatio(source.devicePixelRatio());
  QPainter painter(&result);
  constexpr int cell = 16;
  const int logical_width =
      static_cast<int>(result.deviceIndependentSize().width());
  const int logical_height =
      static_cast<int>(result.deviceIndependentSize().height());
  for (int y = 0; y < logical_height; y += cell) {
    for (int x = 0; x < logical_width; x += cell) {
      const bool alternate = ((x / cell) + (y / cell)) % 2 != 0;
      painter.fillRect(x, y, cell, cell,
                       alternate ? QColor("#29303a") : QColor("#151a20"));
    }
  }
  painter.drawImage(0, 0, source);
  return result;
}

QRect alpha_bounds(const QImage &image) {
  int left = image.width();
  int top = image.height();
  int right = -1;
  int bottom = -1;
  for (int y = 0; y < image.height(); ++y) {
    for (int x = 0; x < image.width(); ++x) {
      if (image.pixelColor(x, y).alpha() == 0)
        continue;
      left = std::min(left, x);
      top = std::min(top, y);
      right = std::max(right, x);
      bottom = std::max(bottom, y);
    }
  }
  return right < left ? QRect{}
                      : QRect(QPoint(left, top), QPoint(right, bottom));
}

std::uint64_t percentile(std::vector<std::uint64_t> values,
                         std::size_t numerator, std::size_t denominator) {
  require(!values.empty() && numerator > 0 && numerator <= denominator,
          "invalid metric population or percentile");
  std::sort(values.begin(), values.end());
  const auto rank = (values.size() * numerator + denominator - 1) / denominator;
  const auto index = std::min(values.size() - 1, rank - 1);
  return values[index];
}

struct Metrics {
  std::uint64_t render_p50_us = 0;
  std::uint64_t render_p95_us = 0;
  std::uint64_t render_max_us = 0;
  std::uint64_t copy_p95_us = 0;
  std::uint64_t input_to_frame_us = 0;
};

Metrics prove_animation_latency_alpha_and_dpr() {
  SceneHarness pet(kPet, 201, 320, 180, 1);
  const auto initial = pet.frame();
  bool transparent = false;
  bool visible = false;
  for (int y = 0; y < initial.image.height(); ++y) {
    for (int x = 0; x < initial.image.width(); ++x) {
      const int alpha = initial.image.pixelColor(x, y).alpha();
      transparent = transparent || alpha == 0;
      visible = visible || alpha > 0;
    }
  }
  require(transparent && visible && initial.image.pixelColor(0, 0).alpha() == 0,
          "pet alpha or transparent clipping boundary regressed");

  const auto key = pet.allocation().surface;
  const auto input_started = Clock::now();
  require(static_cast<bool>(pet.runtime().focus(
              {.surface = key, .sequence = 1, .focused = true})) &&
              static_cast<bool>(pet.runtime().input(
                  pointer(key, 1, surface::ButtonState::pressed))) &&
              static_cast<bool>(pet.runtime().input(
                  pointer(key, 2, surface::ButtonState::released))) &&
              static_cast<bool>(pet.runtime().focus(
                  {.surface = key, .sequence = 2, .focused = false})),
          "pet pointer lifecycle failed");
  FrameSample after_input;
  bool input_changed = false;
  for (int attempt = 0; attempt < 50 && !input_changed; ++attempt) {
    wait_milliseconds(4);
    after_input = pet.frame();
    input_changed = after_input.image != initial.image;
  }
  const auto input_finished = Clock::now();
  require(input_changed && !pet.runtime().focused(),
          "pet input did not start animation or clear focus");

  std::vector<std::uint64_t> render_times;
  std::vector<std::uint64_t> copy_times;
  QImage last = after_input.image;
  bool animated = false;
  for (int frame = 0; frame < 40; ++frame) {
    wait_milliseconds(10);
    auto sample = pet.frame();
    render_times.push_back(sample.render_microseconds);
    copy_times.push_back(sample.copy_microseconds);
    animated = animated || sample.image != last;
    last = std::move(sample.image);
  }
  require(animated, "pet animation produced no changing software frames");

  SceneHarness pet_dpr2(kPet, 202, 320, 180, 2);
  const auto doubled = pet_dpr2.frame();
  require(doubled.image.width() == 640 && doubled.image.height() == 360 &&
              doubled.image.devicePixelRatio() == 2.0,
          "DPR 2 frame lost physical or logical sizing");
  const auto initial_bounds = alpha_bounds(initial.image);
  const auto doubled_bounds = alpha_bounds(doubled.image);
  require(!initial_bounds.isEmpty() &&
              std::abs(doubled_bounds.left() - initial_bounds.left() * 2) <=
                  2 &&
              std::abs(doubled_bounds.top() - initial_bounds.top() * 2) <= 2 &&
              doubled_bounds.width() >= initial_bounds.width() * 2 - 2 &&
              doubled_bounds.height() >= initial_bounds.height() * 2 - 2,
          "DPR 2 pixels did not preserve logical content scale");
  const auto doubled_key = pet_dpr2.allocation().surface;
  const auto doubled_before_input = doubled.image;
  require(static_cast<bool>(pet_dpr2.runtime().focus(
              {.surface = doubled_key, .sequence = 1, .focused = true})) &&
              static_cast<bool>(pet_dpr2.runtime().input(
                  pointer(doubled_key, 1, surface::ButtonState::pressed))) &&
              static_cast<bool>(pet_dpr2.runtime().input(
                  pointer(doubled_key, 2, surface::ButtonState::released))) &&
              static_cast<bool>(pet_dpr2.runtime().focus(
                  {.surface = doubled_key, .sequence = 2, .focused = false})),
          "DPR 2 logical input lifecycle failed");
  bool doubled_input_changed = false;
  for (int attempt = 0; attempt < 50 && !doubled_input_changed; ++attempt) {
    wait_milliseconds(4);
    doubled_input_changed = pet_dpr2.frame().image != doubled_before_input;
  }
  require(doubled_input_changed && !pet_dpr2.runtime().focused(),
          "DPR 2 input coordinates missed the logical pet region");

  std::filesystem::create_directories(kArtifacts);
  require(checkerboard(initial.image)
                  .save(QString::fromStdString(
                      (kArtifacts / "pet-dpr1.png").string())) &&
              checkerboard(doubled.image)
                  .save(QString::fromStdString(
                      (kArtifacts / "pet-dpr2.png").string())),
          "pet visual artifacts could not be saved");

  return {.render_p50_us = percentile(render_times, 50, 100),
          .render_p95_us = percentile(render_times, 95, 100),
          .render_max_us =
              *std::max_element(render_times.begin(), render_times.end()),
          .copy_p95_us = percentile(copy_times, 95, 100),
          .input_to_frame_us = static_cast<std::uint64_t>(
              std::chrono::duration_cast<Microseconds>(input_finished -
                                                       input_started)
                  .count())};
}

void prove_narrow_wide_geometry() {
  NullRuntimeApi narrow_api;
  SceneHarness narrow(kPomodoro, 203, 180, 48, 1, &narrow_api);
  const auto narrow_frame = narrow.frame();
  NullRuntimeApi wide_api;
  SceneHarness wide(kPomodoro, 204, 280, 64, 1, &wide_api);
  const auto wide_frame = wide.frame();
  const auto has_visible_pixels = [](const QImage &image) {
    for (int y = 0; y < image.height(); ++y) {
      for (int x = 0; x < image.width(); ++x) {
        if (image.pixelColor(x, y).alpha() > 0)
          return true;
      }
    }
    return false;
  };
  require(narrow_frame.image.size() == QSize(180, 48) &&
              wide_frame.image.size() == QSize(280, 64) &&
              has_visible_pixels(narrow_frame.image) &&
              has_visible_pixels(wide_frame.image),
          "Pomodoro narrow/wide geometry clipped its root surface");
  require(narrow_frame.image.save(QString::fromStdString(
              (kArtifacts / "pomodoro-narrow.png").string())) &&
              wide_frame.image.save(QString::fromStdString(
                  (kArtifacts / "pomodoro-wide.png").string())),
          "Pomodoro visual artifacts could not be saved");
}

class Placement final : public expressive::PlacementAuthority {
public:
  std::optional<expressive::Placement> place(const host::NamedSurfacePolicy &,
                                             std::uint32_t,
                                             std::uint32_t) noexcept override {
    return next;
  }
  expressive::Placement next{};
};

void prove_host_owned_monitor_transition() {
  const auto parsed =
      manifest::parse_manifest_v2(read_text(kPet / "manifest.json"));
  const auto policy = host::parse_named_surface_policy(parsed, "pet");
  const std::array monitors{
      expressive::Monitor{.id = 11, .width = 1920, .height = 1080},
      expressive::Monitor{.id = 12, .width = 2560, .height = 1440}};
  auto registry = expressive::Registry::create(policy.plugin_id, monitors);
  require(registry.has_value(), "monitor registry was rejected");
  Placement placement;
  placement.next = {.monitor_id = 11, .x = 120, .y = 720};
  const auto first = registry->admit(policy, 1, 320, 180, placement);
  require(first && first->monitor_id == 11 && registry->close(1),
          "first host monitor placement failed");
  placement.next = {.monitor_id = 12, .x = 1800, .y = 1000};
  const auto moved = registry->admit(policy, 2, 320, 180, placement);
  require(moved && moved->monitor_id == 12 && moved->x == 1800 &&
              moved->y == 1000,
          "host-owned monitor transition lost bounds or identity");
}

void write_metrics(const Metrics &metrics) {
  require(metrics.render_p95_us < 100'000 && metrics.render_max_us < 250'000 &&
              metrics.copy_p95_us < 50'000 &&
              metrics.input_to_frame_us < 250'000,
          "measured software render/input cost exceeded the broad proof bound");
  std::ofstream output(kArtifacts / "metrics.tsv", std::ios::trunc);
  require(output.good(), "metrics artifact could not be opened");
  output << "metric\tmicroseconds\n"
         << "render_p50\t" << metrics.render_p50_us << '\n'
         << "render_p95\t" << metrics.render_p95_us << '\n'
         << "render_max\t" << metrics.render_max_us << '\n'
         << "copy_p95\t" << metrics.copy_p95_us << '\n'
         << "input_to_frame\t" << metrics.input_to_frame_us << '\n';
  require(output.good(), "metrics artifact could not be written");
  std::cout << "F2 render_p50_us=" << metrics.render_p50_us
            << " render_p95_us=" << metrics.render_p95_us
            << " render_max_us=" << metrics.render_max_us
            << " copy_p95_us=" << metrics.copy_p95_us
            << " input_to_frame_us=" << metrics.input_to_frame_us << '\n';
}

} // namespace

int main(int argc, char **argv) {
  QGuiApplication application(argc, argv);
  try {
    const auto metrics = prove_animation_latency_alpha_and_dpr();
    prove_narrow_wide_geometry();
    prove_host_owned_monitor_transition();
    write_metrics(metrics);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "render fidelity proof failed: " << error.what() << '\n';
    return 1;
  }
}

#include "render_proof_test.moc"
