#pragma once

#include <sys/socket.h>
#include <sys/types.h>

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace omarchy::plugin_runtime::test_support {

inline constexpr int kWorkerControlFd = 3;
inline constexpr int kWorkerBrokerFd = 4;
inline constexpr int kWorkerRenderFd = 5;

class UniqueFd {
public:
  UniqueFd() = default;
  explicit UniqueFd(int descriptor);
  UniqueFd(const UniqueFd &) = delete;
  UniqueFd &operator=(const UniqueFd &) = delete;
  UniqueFd(UniqueFd &&other) noexcept;
  UniqueFd &operator=(UniqueFd &&other) noexcept;
  ~UniqueFd();

  [[nodiscard]] int get() const;
  [[nodiscard]] explicit operator bool() const;
  [[nodiscard]] int release();
  void reset(int descriptor = -1);

private:
  int descriptor_ = -1;
};

class ManualClock {
public:
  using Tick = std::uint64_t;

  explicit ManualClock(Tick initial = 0);
  [[nodiscard]] Tick now() const;
  [[nodiscard]] Tick deadline_after(Tick duration) const;
  [[nodiscard]] bool expired(Tick deadline) const;
  void advance(Tick duration);

private:
  Tick now_;
};

class DeterministicIdSource {
public:
  explicit DeterministicIdSource(std::uint64_t first);
  [[nodiscard]] std::uint64_t next();

private:
  std::uint64_t next_;
};

struct Mutation {
  std::size_t ordinal;
  std::size_t offset;
  std::byte mask;
  std::vector<std::byte> bytes;
};

[[nodiscard]] std::vector<Mutation>
bounded_mutations(std::span<const std::byte> input,
                  std::size_t maximum_cases = 256);

[[nodiscard]] std::vector<std::byte> decode_hex(std::string_view text);
[[nodiscard]] std::string encode_hex(std::span<const std::byte> bytes);
[[nodiscard]] std::vector<int> open_fd_set();
[[nodiscard]] bool relocate_descriptors_exact(std::span<const int> sources,
                                              std::span<const int> destinations,
                                              unsigned close_from);

struct SeqpacketPair {
  UniqueFd trusted;
  UniqueFd worker;

  [[nodiscard]] static SeqpacketPair create();
};

struct ReceivedPacket {
  std::vector<std::byte> payload;
  ucred credentials{};
  bool has_credentials = false;
  bool truncated = false;
  bool ancillary_invalid = false;
  std::vector<UniqueFd> descriptors;
};

void enable_kernel_credentials(int descriptor);
void send_packet(int descriptor, std::span<const std::byte> payload,
                 std::span<const int> descriptors = {});
[[nodiscard]] ReceivedPacket receive_packet(int descriptor,
                                            std::size_t maximum_payload,
                                            std::size_t maximum_descriptors);

[[nodiscard]] UniqueFd open_pidfd(pid_t process);
enum class PidfdState { alive, exited, unusable };
[[nodiscard]] PidfdState pidfd_state(int descriptor);
[[nodiscard]] bool wait_pidfd_exit(int descriptor, int timeout_milliseconds);
[[nodiscard]] bool bounded_reap(pid_t process, int pidfd,
                                int timeout_milliseconds,
                                int *status_output = nullptr);

class SyntheticResourceTree {
public:
  SyntheticResourceTree();
  SyntheticResourceTree(const SyntheticResourceTree &) = delete;
  SyntheticResourceTree &operator=(const SyntheticResourceTree &) = delete;
  ~SyntheticResourceTree();

  [[nodiscard]] const std::filesystem::path &root() const;
  [[nodiscard]] std::filesystem::path revision() const;
  [[nodiscard]] std::filesystem::path private_state() const;
  [[nodiscard]] std::filesystem::path synthetic_home() const;
  [[nodiscard]] std::filesystem::path sentinel() const;

private:
  std::filesystem::path root_;
};

} // namespace omarchy::plugin_runtime::test_support
