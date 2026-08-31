#include "bus_connection.hpp"
#include "omarchy/plugin_runtime/launcher/launcher.h"

#include <signal.h>
#include <systemd/sd-bus.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <mutex>
#include <ranges>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::launcher {
namespace {

[[nodiscard]] bool append_basic_property(sd_bus_message *message,
                                         const char *name,
                                         const char *signature,
                                         const void *value) {
  return sd_bus_message_open_container(message, 'r', "sv") >= 0 &&
         sd_bus_message_append_basic(message, 's', name) >= 0 &&
         sd_bus_message_open_container(message, 'v', signature) >= 0 &&
         sd_bus_message_append_basic(message, signature[0], value) >= 0 &&
         sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0;
}

[[nodiscard]] bool append_pid_property(sd_bus_message *message,
                                       std::span<const pid_t> processes) {
  if (sd_bus_message_open_container(message, 'r', "sv") < 0 ||
      sd_bus_message_append_basic(message, 's', "PIDs") < 0 ||
      sd_bus_message_open_container(message, 'v', "au") < 0 ||
      sd_bus_message_open_container(message, 'a', "u") < 0) {
    return false;
  }
  for (const pid_t process : processes) {
    const auto pid = static_cast<std::uint32_t>(process);
    if (sd_bus_message_append_basic(message, 'u', &pid) < 0) {
      return false;
    }
  }
  return sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0 &&
         sd_bus_message_close_container(message) >= 0;
}

[[nodiscard]] std::string user_bus_address() {
  return "unix:path=/run/user/" + std::to_string(getuid()) + "/bus";
}

[[nodiscard]] bool bus_disconnected(int result) noexcept {
  return result == -ENOTCONN || result == -ECONNRESET || result == -EPIPE ||
         result == -ECONNABORTED || result == -ESHUTDOWN || result == -EBADF;
}

class SystemdResourceScope final : public ResourceScopeController {
public:
  ~SystemdResourceScope() override {
    sd_bus_unref(cleanup_bus_);
    sd_bus_unref(bus_);
  }

  bool probe(Deadline deadline, std::string &error) override {
    std::unique_lock lock(mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd user manager lock deadline expired";
      return false;
    }
    return probe_locked(deadline, error);
  }

  bool prepare_cleanup(Deadline deadline, std::string &error) override {
    std::unique_lock lock(cleanup_mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd cleanup bus lock deadline expired";
      return false;
    }
    return connect_cleanup_locked(deadline, error);
  }

  AttachResult attach_validated(const ProcessScopeRequest &request,
                                Deadline deadline,
                                std::string &error) override {
    std::unique_lock lock(mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd user manager lock deadline expired";
      return {};
    }
    if (!probe_locked(deadline, error)) return {};
    return attach_locked(request, deadline, error);
  }

  bool terminate_scope_validated(std::string_view unit, Deadline deadline,
                                 std::string &error) noexcept override {
    std::unique_lock lock(cleanup_mutex_, std::defer_lock);
    if (!lock.try_lock_until(deadline)) {
      error = "systemd cleanup bus lock deadline expired";
      return false;
    }
    return terminate_scope_locked(unit, deadline, error);
  }

private:
  void invalidate_primary() noexcept {
    sd_bus_close_unref(bus_);
    bus_ = nullptr;
  }

  [[nodiscard]] bool primary_disconnected(int result) const noexcept {
    return bus_disconnected(result) || sd_bus_is_open(bus_) <= 0 ||
           sd_bus_is_ready(bus_) <= 0;
  }

  bool connect_cleanup_locked(Deadline deadline, std::string &error) noexcept {
    if (cleanup_bus_ != nullptr && !cleanup_failed_ &&
        sd_bus_is_open(cleanup_bus_) > 0)
      return true;
    sd_bus_unref(cleanup_bus_);
    cleanup_bus_ = nullptr;
    cleanup_failed_ = false;
    if (std::chrono::steady_clock::now() >= deadline) {
      error = "systemd cleanup bus setup deadline expired";
      return false;
    }
    cleanup_bus_ = detail::connect_bus(user_bus_address(), deadline, error);
    if (!cleanup_bus_)
      return false;
    return true;
  }

  bool probe_locked(Deadline deadline, std::string &error) {
    const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        deadline - std::chrono::steady_clock::now());
    if (remaining.count() <= 0) {
      error = "systemd user manager deadline expired";
      return false;
    }
    if (bus_ != nullptr) {
      int processed = 0;
      do {
        processed = sd_bus_process(bus_, nullptr);
      } while (processed > 0 &&
               std::chrono::steady_clock::now() < deadline);
      if (processed >= 0 && sd_bus_is_open(bus_) > 0 &&
          sd_bus_is_ready(bus_) > 0)
        return true;
      invalidate_primary();
    }
    bus_ = detail::connect_bus(user_bus_address(), deadline, error);
    if (!bus_) {
      error = "systemd user manager bus is unavailable";
      return false;
    }
    if (sd_bus_set_method_call_timeout(
            bus_, static_cast<std::uint64_t>(remaining.count())) < 0) {
      error = "cannot bound systemd user manager calls";
      sd_bus_unref(bus_);
      bus_ = nullptr;
      return false;
    }
    return true;
  }

  AttachResult attach_locked(const ProcessScopeRequest &request,
                             Deadline deadline, std::string &error) {
    const auto call_remaining =
        std::chrono::duration_cast<std::chrono::microseconds>(
            deadline - std::chrono::steady_clock::now());
    if (call_remaining.count() <= 0) {
      error = "resource-scope attachment deadline expired";
      return {};
    }
    sd_bus_message *message = nullptr;
    sd_bus_message *reply = nullptr;
    sd_bus_error bus_error = SD_BUS_ERROR_NULL;
    const std::string unit_name(request.unit);
    const char *mode = "fail";
    const std::string description(request.description);
    const char *collect_mode = "inactive-or-failed";
    const auto &resources = request.resources;
    const std::uint64_t cpu_quota = resources.cpu_quota_per_second_usec;
    const std::uint64_t memory_high = resources.memory_high_bytes;
    const std::uint64_t memory_max = resources.memory_max_bytes;
    const std::uint64_t tasks_max = resources.tasks_max;
    const std::uint64_t cpu_weight = resources.cpu_weight;
    const std::uint64_t io_weight = resources.io_weight;

    bool attempted = false;
    const int message_result = sd_bus_message_new_method_call(
        bus_, &message, "org.freedesktop.systemd1",
        "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager",
        "StartTransientUnit");
    bool built = message_result >= 0 &&
        sd_bus_message_append_basic(message, 's', unit_name.c_str()) >= 0 &&
        sd_bus_message_append_basic(message, 's', mode) >= 0 &&
        sd_bus_message_open_container(message, 'a', "(sv)") >= 0 &&
        append_basic_property(message, "Description", "s",
                              description.c_str()) &&
        append_pid_property(message, request.pids) &&
        append_basic_property(message, "MemoryHigh", "t", &memory_high) &&
        append_basic_property(message, "MemoryMax", "t", &memory_max) &&
        append_basic_property(message, "TasksMax", "t", &tasks_max) &&
        append_basic_property(message, "CPUQuotaPerSecUSec", "t", &cpu_quota) &&
        append_basic_property(message, "CPUWeight", "t", &cpu_weight) &&
        append_basic_property(message, "IOWeight", "t", &io_weight) &&
        append_basic_property(message, "CollectMode", "s", collect_mode) &&
        sd_bus_message_close_container(message) >= 0 &&
        sd_bus_message_open_container(message, 'a', "(sa(sv))") >= 0 &&
        sd_bus_message_close_container(message) >= 0;
    if (!built) {
      error = "cannot encode transient scope request";
      if (primary_disconnected(message_result))
        invalidate_primary();
    } else {
      attempted = true;
      const std::uint64_t timeout_usec =
          static_cast<std::uint64_t>(call_remaining.count());
      const int call_result =
          sd_bus_call(bus_, message, timeout_usec, &bus_error, &reply);
      if (call_result < 0) {
        error = bus_error.message != nullptr ? bus_error.message
                                             : "StartTransientUnit failed";
        built = false;
        if (primary_disconnected(call_result))
          invalidate_primary();
      }
    }
    if (built) {
      const std::string expected = "/" + unit_name;
      std::vector<bool> applied(request.pids.size(), false);
      while (std::chrono::steady_clock::now() < deadline) {
        for (std::size_t index = 0; index < request.pids.size(); ++index) {
          if (applied[index]) continue;
          std::ifstream cgroup(std::filesystem::path("/proc") /
                               std::to_string(request.pids[index]) / "cgroup");
          std::string record;
          while (std::getline(cgroup, record)) {
            const auto separator = record.find("::");
            if (separator != std::string::npos &&
                record.substr(separator + 2).ends_with(expected)) {
              applied[index] = true;
              break;
            }
          }
        }
        if (std::ranges::all_of(applied, std::identity{})) {
          break;
        }
        const int process_result = sd_bus_process(bus_, nullptr);
        if (process_result < 0) {
          invalidate_primary();
          error = "systemd user manager disconnected during attachment";
          built = false;
          break;
        }
        const auto remaining =
            std::chrono::duration_cast<std::chrono::microseconds>(
                deadline - std::chrono::steady_clock::now());
        if (remaining.count() <= 0) {
          break;
        }
        const int wait_result = sd_bus_wait(
            bus_, static_cast<std::uint64_t>(
                      std::min<std::int64_t>(remaining.count(), 10000)));
        if (wait_result < 0) {
          invalidate_primary();
          error = "systemd user manager disconnected during attachment";
          built = false;
          break;
        }
      }
      if (!std::ranges::all_of(applied, std::identity{})) {
        error = "transient scope did not bind every process before its deadline";
        built = false;
      }
    }
    sd_bus_error_free(&bus_error);
    sd_bus_message_unref(reply);
    sd_bus_message_unref(message);
    return {.attached = built, .cleanup_required = attempted};
  }

  enum class UnitState { present, absent, failed };

  UnitState unit_state_locked(const std::string &name, Deadline deadline,
                              std::string &error) noexcept {
    const auto remaining = std::chrono::duration_cast<std::chrono::microseconds>(
        deadline - std::chrono::steady_clock::now());
    if (remaining.count() <= 0) {
      error = "systemd scope termination deadline expired";
      return UnitState::failed;
    }
    if (sd_bus_set_method_call_timeout(
            cleanup_bus_, static_cast<std::uint64_t>(remaining.count())) < 0) {
      error = "cannot bound systemd scope verification";
      return UnitState::failed;
    }
    sd_bus_error bus_error = SD_BUS_ERROR_NULL;
    sd_bus_message *reply = nullptr;
    const int result = sd_bus_call_method(
        cleanup_bus_, "org.freedesktop.systemd1", "/org/freedesktop/systemd1",
        "org.freedesktop.systemd1.Manager", "GetUnit", &bus_error, &reply,
        "s", name.c_str());
    const bool absent = sd_bus_error_has_name(
        &bus_error, "org.freedesktop.systemd1.NoSuchUnit");
    if (result == -ENOTCONN || result == -ECONNRESET || result == -EPIPE)
      cleanup_failed_ = true;
    if (result < 0 && !absent)
      error = bus_error.message != nullptr
                  ? bus_error.message
                  : "systemd scope verification failed";
    sd_bus_error_free(&bus_error);
    sd_bus_message_unref(reply);
    if (absent) return UnitState::absent;
    return result >= 0 ? UnitState::present : UnitState::failed;
  }

  bool terminate_scope_locked(std::string_view unit, Deadline deadline,
                              std::string &error) noexcept {
    if (!connect_cleanup_locked(deadline, error))
      return false;
    if (sd_bus_is_open(cleanup_bus_) <= 0) {
      cleanup_failed_ = true;
      error = "systemd cleanup bus became unusable";
      return false;
    }
    const std::string name(unit);
    if (unit_state_locked(name, deadline, error) != UnitState::present)
      return error.empty();
    for (const bool kill : {true, false}) {
      const auto remaining =
          std::chrono::duration_cast<std::chrono::microseconds>(
              deadline - std::chrono::steady_clock::now());
      if (remaining.count() <= 0 ||
          sd_bus_set_method_call_timeout(
              cleanup_bus_, static_cast<std::uint64_t>(remaining.count())) < 0) {
        error = "systemd scope termination deadline expired";
        return false;
      }
      sd_bus_error bus_error = SD_BUS_ERROR_NULL;
      sd_bus_message *reply = nullptr;
      const int result = kill
          ? sd_bus_call_method(cleanup_bus_, "org.freedesktop.systemd1",
                               "/org/freedesktop/systemd1",
                               "org.freedesktop.systemd1.Manager", "KillUnit",
                               &bus_error, &reply, "ssi", name.c_str(), "all",
                               SIGKILL)
          : sd_bus_call_method(cleanup_bus_, "org.freedesktop.systemd1",
                               "/org/freedesktop/systemd1",
                               "org.freedesktop.systemd1.Manager", "StopUnit",
                               &bus_error, &reply, "ss", name.c_str(),
                               "replace");
      const bool absent = sd_bus_error_has_name(
          &bus_error, "org.freedesktop.systemd1.NoSuchUnit");
      if (result == -ENOTCONN || result == -ECONNRESET || result == -EPIPE)
        cleanup_failed_ = true;
      if (result < 0 && !absent)
        error = bus_error.message != nullptr
                    ? bus_error.message
                    : "systemd scope termination failed";
      sd_bus_error_free(&bus_error);
      sd_bus_message_unref(reply);
      if (absent) return true;
      if (result < 0) return false;
    }
    while (std::chrono::steady_clock::now() < deadline) {
      const auto state = unit_state_locked(name, deadline, error);
      if (state == UnitState::absent) return true;
      if (state == UnitState::failed) return false;
      const auto remaining =
          std::chrono::duration_cast<std::chrono::microseconds>(
              deadline - std::chrono::steady_clock::now());
      if (remaining.count() <= 0) break;
      static_cast<void>(sd_bus_wait(
          cleanup_bus_, static_cast<std::uint64_t>(
                            std::min<std::int64_t>(remaining.count(), 10000))));
      static_cast<void>(sd_bus_process(cleanup_bus_, nullptr));
    }
    error = "systemd scope termination was not verified before its deadline";
    return false;
  }

  std::timed_mutex mutex_;
  sd_bus *bus_ = nullptr;
  std::timed_mutex cleanup_mutex_;
  sd_bus *cleanup_bus_ = nullptr;
  bool cleanup_failed_ = false;
};

} // namespace

std::shared_ptr<ResourceScopeController>
make_systemd_resource_scope_controller() {
  return std::make_shared<SystemdResourceScope>();
}

} // namespace omarchy::plugin_runtime::launcher
