#include "omarchy/plugin_runtime/providers/provider_schemas.hpp"

#include <algorithm>
#include <limits>

namespace omarchy::plugin_runtime::providers {
namespace {

std::uint16_t get16(std::span<const std::byte> bytes, std::size_t offset) {
  return (std::to_integer<std::uint16_t>(bytes[offset]) << 8U) |
         std::to_integer<std::uint16_t>(bytes[offset + 1]);
}

std::uint32_t get32(std::span<const std::byte> bytes, std::size_t offset) {
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index)
    value =
        (value << 8U) | std::to_integer<std::uint32_t>(bytes[offset + index]);
  return value;
}

void put16(std::span<std::byte> bytes, std::size_t offset,
           std::uint16_t value) {
  bytes[offset] = static_cast<std::byte>(value >> 8U);
  bytes[offset + 1] = static_cast<std::byte>(value);
}

void put32(std::span<std::byte> bytes, std::size_t offset,
           std::uint32_t value) {
  for (std::size_t index = 0; index < 4; ++index)
    bytes[offset + index] =
        static_cast<std::byte>(value >> ((3U - index) * 8U));
}

bool exact_size(std::size_t prefix, std::size_t left, std::size_t right,
                std::size_t actual) {
  if (left > std::numeric_limits<std::size_t>::max() - prefix)
    return false;
  const auto partial = prefix + left;
  return right <= std::numeric_limits<std::size_t>::max() - partial &&
         partial + right == actual;
}

std::string_view text_view(std::span<const std::byte> bytes) {
  return {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
}

} // namespace

bool valid_utf8_text(std::string_view value, bool allow_newline) noexcept {
  if (value.empty() || value.find('\0') != std::string_view::npos)
    return false;
  std::size_t index = 0;
  while (index < value.size()) {
    const auto first = static_cast<unsigned char>(value[index]);
    if (first < 0x80) {
      if (first < 0x20 && !(allow_newline && first == '\n'))
        return false;
      if (first == 0x7f)
        return false;
      ++index;
      continue;
    }
    std::size_t continuation = 0;
    std::uint32_t codepoint = 0;
    if ((first & 0xe0U) == 0xc0U) {
      continuation = 1;
      codepoint = first & 0x1fU;
    } else if ((first & 0xf0U) == 0xe0U) {
      continuation = 2;
      codepoint = first & 0x0fU;
    } else if ((first & 0xf8U) == 0xf0U) {
      continuation = 3;
      codepoint = first & 0x07U;
    } else {
      return false;
    }
    if (continuation >= value.size() - index)
      return false;
    for (std::size_t byte = 1; byte <= continuation; ++byte) {
      const auto next = static_cast<unsigned char>(value[index + byte]);
      if ((next & 0xc0U) != 0x80U)
        return false;
      codepoint = (codepoint << 6U) | (next & 0x3fU);
    }
    const bool overlong = (continuation == 1 && codepoint < 0x80) ||
                          (continuation == 2 && codepoint < 0x800) ||
                          (continuation == 3 && codepoint < 0x10000);
    if (overlong || codepoint > 0x10ffff ||
        (codepoint >= 0xd800 && codepoint <= 0xdfff))
      return false;
    index += continuation + 1;
  }
  return true;
}

bool valid_storage_key(std::string_view value) noexcept {
  if (value.empty() || value.size() > kMaximumStorageKeyBytes || value == "." ||
      value == "..")
    return false;
  return std::all_of(value.begin(), value.end(), [](char character) {
    const auto byte = static_cast<unsigned char>(character);
    return (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') ||
           (byte >= '0' && byte <= '9') || byte == '.' || byte == '_' ||
           byte == '-';
  });
}

bool decode_storage_read(std::span<const std::byte> input,
                         StorageReadRequest &output) noexcept {
  if (input.size() < 2)
    return false;
  const auto length = get16(input, 0);
  if (length > kMaximumStorageKeyBytes ||
      !exact_size(2, length, 0, input.size()))
    return false;
  const auto key = text_view(input.subspan(2, length));
  if (!valid_storage_key(key))
    return false;
  output = {.key = key};
  return true;
}

bool decode_storage_write(std::span<const std::byte> input,
                          StorageWriteRequest &output) noexcept {
  if (input.size() < 6)
    return false;
  const auto key_length = get16(input, 0);
  const auto value_length = get32(input, 2);
  if (key_length > kMaximumStorageKeyBytes ||
      value_length > kMaximumStorageValueBytes ||
      !exact_size(6, key_length, value_length, input.size()))
    return false;
  const auto key = text_view(input.subspan(6, key_length));
  if (!valid_storage_key(key))
    return false;
  output = {.key = key, .value = input.subspan(6 + key_length, value_length)};
  return true;
}

bool decode_notification(std::span<const std::byte> input,
                         NotificationRequest &output) noexcept {
  if (input.size() < 4)
    return false;
  const auto title_length = get16(input, 0);
  const auto body_length = get16(input, 2);
  if (title_length > kMaximumNotificationTitleBytes ||
      body_length > kMaximumNotificationBodyBytes ||
      !exact_size(4, title_length, body_length, input.size()))
    return false;
  const auto title = text_view(input.subspan(4, title_length));
  const auto body = text_view(input.subspan(4 + title_length, body_length));
  if (!valid_utf8_text(title, false) || !valid_utf8_text(body, true))
    return false;
  output = {.title = title, .body = body};
  return true;
}

bool decode_fake_acknowledge(std::span<const std::byte> input,
                             FakeAcknowledgeRequest &output) noexcept {
  if (input.size() != 4)
    return false;
  output.status = get32(input, 0);
  return output.status != 0;
}

bool encode_storage_read_result(bool found, std::span<const std::byte> value,
                                std::span<std::byte> output,
                                std::size_t &bytes_written) noexcept {
  bytes_written = 0;
  if ((!found && !value.empty()) || value.size() > kMaximumStorageValueBytes ||
      output.size() < 8 + value.size())
    return false;
  output[0] = found ? std::byte{1} : std::byte{0};
  output[1] = output[2] = output[3] = std::byte{0};
  put32(output, 4, static_cast<std::uint32_t>(value.size()));
  std::copy(value.begin(), value.end(), output.begin() + 8);
  bytes_written = 8 + value.size();
  return true;
}

bool encode_fake_status_result(std::span<const FakeStatusView> statuses,
                               std::span<std::byte> output,
                               std::size_t &bytes_written) noexcept {
  bytes_written = 0;
  if (statuses.size() > kMaximumFakeStatuses || output.size() < 4)
    return false;
  std::size_t required = 4;
  for (const auto &status : statuses) {
    if (status.id == 0 || status.text.size() > kMaximumFakeStatusTextBytes ||
        !valid_utf8_text(status.text, false) ||
        status.text.size() > std::numeric_limits<std::uint16_t>::max() ||
        required >
            std::numeric_limits<std::size_t>::max() - 10 - status.text.size())
      return false;
    required += 10 + status.text.size();
  }
  if (output.size() < required)
    return false;
  put16(output, 0, static_cast<std::uint16_t>(statuses.size()));
  put16(output, 2, 0);
  std::size_t offset = 4;
  for (const auto &status : statuses) {
    put32(output, offset, status.id);
    output[offset + 4] = status.acknowledged ? std::byte{1} : std::byte{0};
    output[offset + 5] = std::byte{0};
    put16(output, offset + 6, static_cast<std::uint16_t>(status.text.size()));
    put16(output, offset + 8, 0);
    std::copy(reinterpret_cast<const std::byte *>(status.text.data()),
              reinterpret_cast<const std::byte *>(status.text.data() +
                                                  status.text.size()),
              output.begin() + static_cast<std::ptrdiff_t>(offset + 10));
    offset += 10 + status.text.size();
  }
  bytes_written = required;
  return true;
}

} // namespace omarchy::plugin_runtime::providers
