#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace omarchy::plugin_runtime::providers {

inline constexpr std::size_t kMaximumStorageKeyBytes = 64;
inline constexpr std::size_t kMaximumStorageValueBytes = 4096;
inline constexpr std::size_t kMaximumNotificationTitleBytes = 96;
inline constexpr std::size_t kMaximumNotificationBodyBytes = 512;
inline constexpr std::size_t kMaximumFakeStatusTextBytes = 160;
inline constexpr std::size_t kMaximumFakeStatuses = 16;

struct StorageReadRequest {
  std::string_view key;
};

struct StorageWriteRequest {
  std::string_view key;
  std::span<const std::byte> value;
};

struct NotificationRequest {
  std::string_view title;
  std::string_view body;
};

struct FakeAcknowledgeRequest {
  std::uint32_t status = 0;
};

struct FakeStatusView {
  std::uint32_t id = 0;
  bool acknowledged = false;
  std::string_view text;
};

[[nodiscard]] bool decode_storage_read(std::span<const std::byte> input,
                                       StorageReadRequest &output) noexcept;
[[nodiscard]] bool decode_storage_write(std::span<const std::byte> input,
                                        StorageWriteRequest &output) noexcept;
[[nodiscard]] bool decode_notification(std::span<const std::byte> input,
                                       NotificationRequest &output) noexcept;
[[nodiscard]] bool
decode_fake_acknowledge(std::span<const std::byte> input,
                        FakeAcknowledgeRequest &output) noexcept;

[[nodiscard]] bool
encode_storage_read_result(bool found, std::span<const std::byte> value,
                           std::span<std::byte> output,
                           std::size_t &bytes_written) noexcept;
[[nodiscard]] bool
encode_fake_status_result(std::span<const FakeStatusView> statuses,
                          std::span<std::byte> output,
                          std::size_t &bytes_written) noexcept;

[[nodiscard]] bool valid_utf8_text(std::string_view value,
                                   bool allow_newline) noexcept;
[[nodiscard]] bool valid_storage_key(std::string_view value) noexcept;

} // namespace omarchy::plugin_runtime::providers
