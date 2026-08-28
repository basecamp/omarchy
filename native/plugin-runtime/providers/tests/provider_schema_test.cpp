#include "omarchy/plugin_runtime/providers/provider_schemas.hpp"

#include <array>
#include <cstddef>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

namespace providers = omarchy::plugin_runtime::providers;

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

} // namespace

int main() {
  const std::array read{std::byte{0x00}, std::byte{0x05}, std::byte{'t'},
                        std::byte{'i'},  std::byte{'m'},  std::byte{'e'},
                        std::byte{'r'}};
  providers::StorageReadRequest read_request{};
  require(providers::decode_storage_read(read, read_request) &&
              read_request.key == "timer",
          "literal storage-read vector changed");
  auto read_length_mutation = read;
  read_length_mutation[1] = std::byte{0x06};
  require(!providers::decode_storage_read(read_length_mutation, read_request),
          "storage-read length mutation was accepted");

  const std::array write{
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x02},
      std::byte{'k'},  std::byte{0xaa}, std::byte{0xbb},
  };
  providers::StorageWriteRequest write_request{};
  require(providers::decode_storage_write(write, write_request) &&
              write_request.key == "k" && write_request.value.size() == 2 &&
              write_request.value[0] == std::byte{0xaa},
          "literal storage-write vector changed");
  auto write_trailing_mutation = write;
  write_trailing_mutation.back() = std::byte{0};
  write_trailing_mutation[5] = std::byte{0x01};
  require(
      !providers::decode_storage_write(write_trailing_mutation, write_request),
      "storage-write trailing byte was accepted");

  const std::array notification{
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x02},
      std::byte{'T'},  std::byte{'O'},  std::byte{'K'},
  };
  providers::NotificationRequest notification_request{};
  require(providers::decode_notification(notification, notification_request) &&
              notification_request.title == "T" &&
              notification_request.body == "OK",
          "literal notification vector changed");
  auto notification_control_mutation = notification;
  notification_control_mutation[4] = std::byte{0x1b};
  require(!providers::decode_notification(notification_control_mutation,
                                          notification_request),
          "notification control character was accepted");

  const std::array acknowledge{std::byte{0x00}, std::byte{0x00},
                               std::byte{0x00}, std::byte{0x2a}};
  providers::FakeAcknowledgeRequest acknowledge_request{};
  require(
      providers::decode_fake_acknowledge(acknowledge, acknowledge_request) &&
          acknowledge_request.status == 42,
      "literal fake acknowledgement vector changed");
  const std::array zero_ack{std::byte{0}, std::byte{0}, std::byte{0},
                            std::byte{0}};
  require(!providers::decode_fake_acknowledge(zero_ack, acknowledge_request),
          "zero fake status id was accepted");

  const std::array value{std::byte{0xaa}, std::byte{0xbb}};
  std::array<std::byte, 32> encoded{};
  std::size_t written = 0;
  require(
      providers::encode_storage_read_result(true, value, encoded, written) &&
          written == 10 && encoded[0] == std::byte{1} &&
          encoded[4] == std::byte{0} && encoded[7] == std::byte{2} &&
          encoded[8] == value[0] && encoded[9] == value[1],
      "literal storage result vector changed");
  require(
      !providers::encode_storage_read_result(false, value, encoded, written),
      "not-found storage result carried bytes");

  const std::array statuses{
      providers::FakeStatusView{.id = 42, .acknowledged = true, .text = "OK"},
  };
  require(providers::encode_fake_status_result(statuses, encoded, written) &&
              written == 16 && encoded[0] == std::byte{0} &&
              encoded[1] == std::byte{1} && encoded[4] == std::byte{0} &&
              encoded[7] == std::byte{42} && encoded[8] == std::byte{1} &&
              encoded[14] == std::byte{'O'} && encoded[15] == std::byte{'K'},
          "literal fake-status result vector changed");
  require(!providers::encode_fake_status_result(
              statuses, std::span<std::byte>(encoded).first(15), written),
          "truncated fake-status output was accepted");

  require(providers::valid_utf8_text("caf\xc3\xa9", false),
          "valid UTF-8 was rejected");
  require(!providers::valid_utf8_text("\xc0\x80", false),
          "overlong UTF-8 was accepted");
  require(!providers::valid_storage_key("a/b"),
          "storage key accepted a separator");

  return 0;
}
