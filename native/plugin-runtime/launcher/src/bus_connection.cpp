#include "bus_connection.hpp"

#include <poll.h>
#include <systemd/sd-bus.h>
#include <time.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <limits>
#include <string>

namespace omarchy::plugin_runtime::launcher::detail {
namespace {

[[nodiscard]] timespec wait_duration(Deadline deadline,
                                     std::uint64_t bus_timeout) noexcept {
  auto remaining = deadline - std::chrono::steady_clock::now();
  if (bus_timeout != std::numeric_limits<std::uint64_t>::max()) {
    timespec monotonic{};
    if (clock_gettime(CLOCK_MONOTONIC, &monotonic) == 0) {
      const auto now_usec =
          static_cast<std::uint64_t>(monotonic.tv_sec) * 1000000ULL +
          static_cast<std::uint64_t>(monotonic.tv_nsec / 1000);
      const auto bus_remaining =
          bus_timeout > now_usec
              ? std::chrono::microseconds(bus_timeout - now_usec)
              : std::chrono::microseconds::zero();
      remaining = std::min(remaining,
                           std::chrono::duration_cast<
                               std::chrono::steady_clock::duration>(
                               bus_remaining));
    }
  }
  if (remaining <= std::chrono::steady_clock::duration::zero())
    return {};
  const auto nanoseconds =
      std::chrono::duration_cast<std::chrono::nanoseconds>(remaining);
  return {.tv_sec = static_cast<time_t>(nanoseconds.count() / 1000000000LL),
          .tv_nsec = static_cast<long>(nanoseconds.count() % 1000000000LL)};
}

} // namespace

sd_bus *connect_bus(std::string_view address, Deadline deadline,
                    std::string &error) noexcept {
  error.clear();
  if (address.empty() || std::chrono::steady_clock::now() >= deadline) {
    error = "bus connection deadline expired";
    return nullptr;
  }

  sd_bus *bus = nullptr;
  const auto reject = [&](std::string message) {
    sd_bus_close_unref(bus);
    bus = nullptr;
    error = std::move(message);
  };
  const std::string owned_address(address);
  if (sd_bus_new(&bus) < 0 ||
      sd_bus_set_address(bus, owned_address.c_str()) < 0 ||
      sd_bus_set_bus_client(bus, 1) < 0 || sd_bus_start(bus) < 0) {
    reject("bus connection could not start");
    return nullptr;
  }

  while (std::chrono::steady_clock::now() < deadline) {
    int processed = 0;
    do {
      processed = sd_bus_process(bus, nullptr);
    } while (processed > 0 &&
             std::chrono::steady_clock::now() < deadline);
    if (processed < 0) {
      reject("bus connection failed during authentication");
      return nullptr;
    }
    if (std::chrono::steady_clock::now() >= deadline)
      break;
    if (sd_bus_is_ready(bus) > 0)
      return bus;

    const int descriptor = sd_bus_get_fd(bus);
    const int events = sd_bus_get_events(bus);
    std::uint64_t bus_timeout =
        std::numeric_limits<std::uint64_t>::max();
    if (descriptor < 0 || events < 0 ||
        sd_bus_get_timeout(bus, &bus_timeout) < 0) {
      reject("bus connection wait state is invalid");
      return nullptr;
    }
    pollfd ready{.fd = descriptor,
                 .events = static_cast<short>(events),
                 .revents = 0};
    const timespec timeout = wait_duration(deadline, bus_timeout);
    const int polled = ppoll(&ready, 1, &timeout, nullptr);
    if (polled < 0 && errno != EINTR) {
      reject("bus connection polling failed");
      return nullptr;
    }
  }

  reject("bus connection deadline expired");
  return nullptr;
}

} // namespace omarchy::plugin_runtime::launcher::detail
