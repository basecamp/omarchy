#include "omarchy/plugin_runtime/test_support/test_support.h"

#if OMARCHY_TEST_HAS_MANIFEST
#include "manifest_contract.hpp"
#endif
#if OMARCHY_TEST_HAS_SURFACE
#include "omarchy/plugin_runtime/surface/render_messages.hpp"
#include "omarchy/plugin_runtime/surface/shared_layout.hpp"
#endif
#if OMARCHY_TEST_HAS_WIRE
#include "omarchy/plugin/wire/envelope.hpp"
#endif

#include <fcntl.h>

#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace support = omarchy::plugin_runtime::test_support;

namespace {
[[noreturn]] void fail(std::string_view message) {
  std::cerr << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

std::string read_text(const std::filesystem::path &path) {
  std::ifstream stream(path);
  if (!stream) {
    throw std::runtime_error("cannot open fixture: " + path.string());
  }
  return {std::istreambuf_iterator<char>(stream),
          std::istreambuf_iterator<char>()};
}

std::map<std::string, std::string>
read_expectation(const std::filesystem::path &path) {
  std::ifstream stream(path);
  std::map<std::string, std::string> output;
  std::string line;
  while (std::getline(stream, line)) {
    const auto separator = line.find('=');
    if (separator == std::string::npos || separator == 0 ||
        separator + 1 == line.size() ||
        !output.emplace(line.substr(0, separator), line.substr(separator + 1))
             .second) {
      throw std::runtime_error("invalid fixture expectation: " + path.string());
    }
  }
  return output;
}

void deterministic_support_test() {
  support::ManualClock clock(100);
  const auto deadline = clock.deadline_after(25);
  require(!clock.expired(deadline), "manual clock expired early");
  clock.advance(24);
  require(!clock.expired(deadline), "manual clock ignored boundary");
  clock.advance(1);
  require(clock.expired(deadline), "manual clock did not expire at boundary");

  support::DeterministicIdSource ids(0x1000);
  require(ids.next() == 0x1000 && ids.next() == 0x1001,
          "deterministic id sequence changed");

  const std::array input{std::byte{0x10}, std::byte{0x20}, std::byte{0x30}};
  const auto first = support::bounded_mutations(input, 8);
  const auto second = support::bounded_mutations(input, 8);
  require(first.size() == 8 && second.size() == first.size(),
          "mutation count is not bounded");
  for (std::size_t index = 0; index < first.size(); ++index) {
    require(first.at(index).ordinal == index &&
                first.at(index).bytes == second.at(index).bytes &&
                first.at(index).offset == second.at(index).offset &&
                first.at(index).mask == second.at(index).mask,
            "mutation order is not deterministic");
  }
  require(support::decode_hex(support::encode_hex(input)) ==
              std::vector<std::byte>(input.begin(), input.end()),
          "hex fixture codec is not lossless");
}

void synthetic_resource_test() {
  std::filesystem::path root;
  {
    support::SyntheticResourceTree tree;
    root = tree.root();
    require(root.string().starts_with("/tmp/omarchy-plugin-fixture."),
            "synthetic tree escaped its dedicated /tmp prefix");
    require(std::filesystem::is_regular_file(tree.revision() / "plugin.qml") &&
                std::filesystem::is_regular_file(tree.sentinel()) &&
                std::filesystem::is_directory(tree.private_state()),
            "synthetic sandbox resources are incomplete");
  }
  require(!std::filesystem::exists(root),
          "synthetic sandbox resources survived fixture teardown");
}

void descriptor_support_test() {
  const auto before = support::open_fd_set();
  {
    support::UniqueFd descriptor(open("/dev/null", O_RDONLY | O_CLOEXEC));
    require(static_cast<bool>(descriptor), "UniqueFd fixture could not open");
    const auto during = support::open_fd_set();
    require(during.size() == before.size() + 1,
            "open descriptor fixture is not observable");
  }
  require(support::open_fd_set() == before,
          "UniqueFd fixture leaked a descriptor");
}

#if OMARCHY_TEST_HAS_WIRE
omarchy::plugin::wire::EndpointRole role_from_string(std::string_view value) {
  using omarchy::plugin::wire::EndpointRole;
  if (value == "control") {
    return EndpointRole::control;
  }
  if (value == "broker") {
    return EndpointRole::broker;
  }
  if (value == "render") {
    return EndpointRole::render;
  }
  throw std::runtime_error("unknown fixture endpoint role");
}

omarchy::plugin::wire::FatalReason reason_from_string(std::string_view value) {
  using omarchy::plugin::wire::FatalReason;
  if (value == "invalid_magic") {
    return FatalReason::invalid_magic;
  }
  if (value == "endpoint_role_mismatch") {
    return FatalReason::endpoint_role_mismatch;
  }
  if (value == "packet_too_short") {
    return FatalReason::packet_too_short;
  }
  throw std::runtime_error("unknown fixture fatal reason");
}

void wire_corpus_test() {
  namespace wire = omarchy::plugin::wire;
  const std::filesystem::path root(WIRE_FIXTURE_ROOT);
  std::vector<std::filesystem::path> cases;
  for (const auto &entry : std::filesystem::directory_iterator(root)) {
    if (entry.path().extension() == ".hex") {
      cases.push_back(entry.path());
    }
  }
  std::ranges::sort(cases);
  require(cases.size() == 5, "wire corpus case count changed unexpectedly");

  for (const auto &hex_path : cases) {
    const auto expectation = read_expectation(
        hex_path.parent_path() / (hex_path.stem().string() + ".expect"));
    const auto role = role_from_string(expectation.at("trusted_role"));
    const auto bytes = support::decode_hex(read_text(hex_path));
    const auto decoded = wire::decode_packet(bytes, role);
    if (expectation.at("result") == "ok") {
      require(static_cast<bool>(decoded), "valid literal wire fixture failed");
      const auto payload_size =
          static_cast<std::size_t>(std::stoul(expectation.at("payload_size")));
      require(decoded.packet.payload.size() == payload_size,
              "literal wire payload size changed");
      std::vector<std::byte> encoded(bytes.size());
      const auto result = wire::encode_packet(decoded.packet.header,
                                              decoded.packet.payload, encoded);
      require(static_cast<bool>(result) && encoded == bytes,
              "literal wire fixture no longer round-trips exactly");
    } else {
      require(decoded.error == reason_from_string(expectation.at("result")),
              "literal wire fixture failed for a different reason");
    }

    const auto first = support::bounded_mutations(bytes, 128);
    const auto second = support::bounded_mutations(bytes, 128);
    require(first.size() == second.size(),
            "wire mutation campaign changed size");
    for (std::size_t index = 0; index < first.size(); ++index) {
      require(first.at(index).bytes == second.at(index).bytes,
              "wire mutation campaign changed order");
      static_cast<void>(wire::decode_packet(first.at(index).bytes, role));
    }
  }

  for (const auto role :
       {wire::EndpointRole::control, wire::EndpointRole::broker,
        wire::EndpointRole::render}) {
    const auto cap = wire::payload_cap(role);
    std::vector<std::byte> payload(cap);
    std::vector<std::byte> output(wire::kHeaderSize + payload.size());
    const wire::EnvelopeHeader header{.endpoint_role = role,
                                      .message_type = 0x1100,
                                      .role_protocol_version = 1,
                                      .launch_generation = 1,
                                      .correlation_id = 1};
    require(static_cast<bool>(wire::encode_packet(header, payload, output)),
            "endpoint cap fixture was rejected");
    payload.push_back(std::byte{0});
    output.push_back(std::byte{0});
    require(wire::encode_packet(header, payload, output).error ==
                wire::FatalReason::payload_cap_exceeded,
            "one-byte-over endpoint fixture was accepted");
  }
}
#endif

#if OMARCHY_TEST_HAS_MANIFEST
void manifest_fake_test() {
  namespace manifest = omarchy::plugins::manifest;
  support::DeterministicIdSource ids(0x2000);
  manifest::Lifecycle lifecycle;
  lifecycle.stage(manifest::sha256_hex(std::to_string(ids.next())));
  lifecycle.validation_succeeded(true);
  lifecycle.candidate_health_succeeded();
  require(lifecycle.active().has_value() && !lifecycle.pending().has_value(),
          "deterministic lifecycle fake did not activate");
  lifecycle.stage(manifest::sha256_hex(std::to_string(ids.next())));
  lifecycle.validation_succeeded(false);
  require(lifecycle.pending().has_value() &&
              lifecycle.pending()->state ==
                  manifest::RevisionState::awaiting_grants,
          "deterministic lifecycle fake did not wait for grants");
}
#endif

#if OMARCHY_TEST_HAS_SURFACE
void render_fake_test() {
  namespace surface = omarchy::plugin_runtime::surface;
  support::DeterministicIdSource ids(0x3000);
  const auto allocation =
      surface::make_allocation({.id = ids.next(), .generation = ids.next()},
                               320, 96, 640, 192, 2, 1, 4096);
  require(allocation.has_value(), "deterministic surface allocation failed");
  const surface::FrameReady frame{.surface = allocation->surface,
                                  .slot = 1,
                                  .slot_sequence = 2,
                                  .frame_sequence = 1};
  const auto bytes = surface::encode_frame_ready(frame);
  surface::FrameReady decoded{};
  require(surface::decode_frame_ready(bytes, decoded) &&
              decoded.surface == frame.surface && decoded.slot == frame.slot &&
              decoded.slot_sequence == frame.slot_sequence &&
              decoded.frame_sequence == frame.frame_sequence,
          "render fake does not use the B4 public codec");
  for (const auto &mutation : support::bounded_mutations(bytes, 64)) {
    static_cast<void>(surface::decode_frame_ready(mutation.bytes, decoded));
  }
}
#endif
} // namespace

int main() {
  deterministic_support_test();
  synthetic_resource_test();
  descriptor_support_test();
#if OMARCHY_TEST_HAS_WIRE
  wire_corpus_test();
#endif
#if OMARCHY_TEST_HAS_MANIFEST
  manifest_fake_test();
#endif
#if OMARCHY_TEST_HAS_SURFACE
  render_fake_test();
#endif
  return 0;
}
