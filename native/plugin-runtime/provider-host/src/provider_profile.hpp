#pragma once

#include "omarchy/plugin_runtime/provider_host/provider_host.hpp"

#include <unistd.h>

#include <chrono>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace omarchy::plugin_runtime::provider_host::detail {

class Descriptor final {
public:
  Descriptor() = default;
  explicit Descriptor(int value) : value_(value) {}
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
  Descriptor(Descriptor &&other) noexcept
      : value_(std::exchange(other.value_, -1)) {}
  Descriptor &operator=(Descriptor &&other) noexcept {
    if (this != &other) {
      reset();
      value_ = std::exchange(other.value_, -1);
    }
    return *this;
  }
  ~Descriptor() { reset(); }

  [[nodiscard]] int get() const noexcept { return value_; }
  [[nodiscard]] explicit operator bool() const noexcept { return value_ >= 0; }
  int release() noexcept { return std::exchange(value_, -1); }
  void reset(int value = -1) noexcept {
    if (value_ >= 0)
      ::close(value_);
    value_ = value;
  }

private:
  int value_ = -1;
};

} // namespace omarchy::plugin_runtime::provider_host::detail

namespace omarchy::plugin_runtime::provider_host {

struct ProviderCatalog::Profile final {
  definitions::AdapterBinding binding;
  std::string group;
  std::string executable_path;
  definitions::Digest executable_digest;
  std::vector<std::string> arguments;
  std::optional<std::chrono::milliseconds> invocation_timeout;
  detail::Descriptor executable;
};

} // namespace omarchy::plugin_runtime::provider_host
