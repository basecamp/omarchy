#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/control.hpp"
#include "omarchy/plugin/wire/permission_snapshot.hpp"
#include "omarchy/plugin/wire/role_registry.hpp"
#include "omarchy/plugin/wire/state.hpp"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

namespace {

using namespace omarchy::plugin::wire;

constexpr std::uint64_t kGeneration = 0x0102030405060708ULL;
constexpr std::uint64_t kCorrelation = 0x1112131415161718ULL;
constexpr std::uint16_t kRequestType = 0x1100;
constexpr std::uint16_t kResponseType = 0x1101;
constexpr std::uint16_t kEventType = 0x1102;

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

std::vector<std::byte> encode(const EnvelopeHeader &header,
                              std::span<const std::byte> payload = {}) {
  std::vector<std::byte> output(kHeaderSize + payload.size());
  const auto result = encode_packet(header, payload, output);
  require(static_cast<bool>(result) && result.bytes_written == output.size(),
          "packet encoding failed");
  return output;
}

EnvelopeHeader sequenced_header(EndpointRole role, std::uint16_t type,
                                std::uint64_t sequence,
                                std::uint64_t correlation = 0) {
  return {.endpoint_role = role,
          .message_type = type,
          .role_protocol_version = 1,
          .launch_generation = kGeneration,
          .correlation_id = correlation,
          .lane_sequence = sequence};
}

constexpr std::uint64_t lane_value(EndpointRole role, std::uint64_t counter) {
  return (counter << 2U) | static_cast<std::uint16_t>(role);
}

std::string hex(std::span<const std::byte> bytes) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (const auto byte : bytes) {
    output << std::setw(2) << std::to_integer<unsigned int>(byte);
  }
  return output.str();
}

EnvelopeHeader selected_header(EndpointRole role, std::uint16_t type,
                               std::uint64_t correlation = 0) {
  return EnvelopeHeader{.endpoint_role = role,
                        .message_type = type,
                        .role_protocol_version = 1,
                        .launch_generation = kGeneration,
                        .correlation_id = correlation,
                        .lane_sequence =
                            type == static_cast<std::uint16_t>(
                                        CommonMessageType::welcome)
                                ? 0
                                : lane_value(role, 1)};
}

void golden_test() {
  const auto hello_payload =
      encode_hello_payload(HelloPayload{VersionRange{1, 1}});
  const auto hello = encode(
      EnvelopeHeader{.endpoint_role = EndpointRole::control}, hello_payload);
  require(hex(hello) ==
              "4f4d504c00020030000100010000000000000004000000000000000000000000"
              "0000000000000000000000000000000000010001",
          "HELLO literal golden mismatch");

  const auto welcome_payload = encode_welcome_payload({4096, 4});
  const auto welcome = encode(
      selected_header(EndpointRole::control,
                      static_cast<std::uint16_t>(CommonMessageType::welcome)),
      welcome_payload);
  require(hex(welcome) ==
              "4f4d504c00020030000100020001000000000008000000000102030405060708"
              "000000000000000000000000000000000000100000000004",
          "WELCOME literal golden mismatch");

  const auto failed_payload = encode_negotiation_failed_payload(
      {NegotiationFailure::no_common_role_version, {1, 1}});
  const auto failed =
      encode(EnvelopeHeader{.endpoint_role = EndpointRole::render,
                            .message_type = static_cast<std::uint16_t>(
                                CommonMessageType::negotiation_failed)},
             failed_payload);
  require(hex(failed) ==
              "4f4d504c00020030000300030000000000000006000000000000000000000000"
              "00000000000000000000000000000000000100010001",
          "NEGOTIATION_FAILED literal golden mismatch");

  const std::array<std::byte, 2> reason{std::byte{0}, std::byte{1}};
  const auto typed = encode(selected_header(EndpointRole::broker,
                                            static_cast<std::uint16_t>(
                                                CommonMessageType::typed_error),
                                            kCorrelation),
                            reason);
  require(hex(typed) ==
              "4f4d504c00020030000200040001000000000002000000000102030405060708"
              "111213141516171800000000000000060001",
          "TYPED_ERROR literal golden mismatch");

  const auto cancel = encode(selected_header(
      EndpointRole::broker,
      static_cast<std::uint16_t>(CommonMessageType::cancel), kCorrelation));
  require(hex(cancel) ==
              "4f4d504c00020030000200050001000000000000000000000102030405060708"
              "11121314151617180000000000000006",
          "CANCEL literal golden mismatch");

  const auto cancel_result =
      encode(selected_header(
                 EndpointRole::broker,
                 static_cast<std::uint16_t>(CommonMessageType::cancel_result),
                 kCorrelation),
             encode_cancel_result_payload(CancelOutcome::accepted));
  require(hex(cancel_result) ==
              "4f4d504c00020030000200060001000000000002000000000102030405060708"
              "111213141516171800000000000000060001",
          "CANCEL_RESULT literal golden mismatch");

  const auto protocol_error = encode(
      selected_header(
          EndpointRole::broker,
          static_cast<std::uint16_t>(CommonMessageType::protocol_error)),
      encode_protocol_error_payload(ProtocolErrorReason::invalid_message));
  require(hex(protocol_error) ==
              "4f4d504c00020030000200070001000000000002000000000102030405060708"
              "000000000000000000000000000000060001",
          "PROTOCOL_ERROR literal golden mismatch");

  const std::array<std::byte, 2> payload{std::byte{0xaa}, std::byte{0x55}};
  const auto sequenced = encode(sequenced_header(
                                    EndpointRole::broker, kRequestType,
                                    0x212223242526272aULL, kCorrelation),
                                payload);
  require(
      hex(sequenced) ==
          "4f4d504c00020030000211000001000000000002000000000102030405060708"
          "1112131415161718212223242526272aaa55",
      "envelope literal golden or sequence offset mismatch");
}

void envelope_and_sequence_test() {
  static_assert(!std::is_copy_constructible_v<SessionSequence>);
  static_assert(!std::is_move_constructible_v<SessionSequence>);
  const auto valid = encode(sequenced_header(
      EndpointRole::broker, kRequestType,
      lane_value(EndpointRole::broker, 1), kCorrelation));
  const auto decoded = decode_packet(valid, EndpointRole::broker);
  require(decoded && decoded.packet.header.envelope_version ==
                         kEnvelopeVersion &&
              decoded.packet.header.header_size == kHeaderSize &&
              decoded.packet.header.lane_sequence ==
                  lane_value(EndpointRole::broker, 1),
          "envelope did not decode exactly");

  auto crossed = sequenced_header(EndpointRole::broker, kRequestType,
                                  lane_value(EndpointRole::broker, 1),
                                  kCorrelation);
  crossed.header_size = 40;
  std::array<std::byte, kHeaderSize> output{};
  require(encode_packet(crossed, {}, output).error ==
              FatalReason::invalid_header_size,
          "sole envelope accepted a noncanonical header size");
  auto crossed_bytes = valid;
  crossed_bytes[6] = std::byte{0};
  crossed_bytes[7] = std::byte{40};
  require(decode_packet(crossed_bytes, EndpointRole::broker).error ==
              FatalReason::invalid_header_size,
          "decoder accepted a noncanonical header size");

  auto unsupported = valid;
  unsupported[4] = std::byte{0};
  unsupported[5] = std::byte{1};
  require(decode_packet(unsupported, EndpointRole::broker).error ==
              FatalReason::unsupported_envelope_version,
          "decoder accepted literal unsupported envelope version 1");

  auto zero =
      sequenced_header(EndpointRole::broker, kRequestType, 0, kCorrelation);
  require(encode_packet(zero, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "post-ready packet accepted sequence zero");
  auto wrong_tag = sequenced_header(EndpointRole::control, kRequestType,
                                    lane_value(EndpointRole::broker, 1),
                                    kCorrelation);
  require(encode_packet(wrong_tag, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "envelope accepted a sequence tagged for another lane");
  auto sequenced_hello = sequenced_header(
      EndpointRole::control,
      static_cast<std::uint16_t>(CommonMessageType::hello), 1);
  sequenced_hello.role_protocol_version = 0;
  sequenced_hello.launch_generation = 0;
  require(encode_packet(sequenced_hello, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "HELLO accepted a nonzero sequence");

  SessionSequence sequence;
  const auto control = sequence.take_outbound(EndpointRole::control);
  const auto broker = sequence.take_outbound(EndpointRole::broker);
  const auto render = sequence.take_outbound(EndpointRole::render);
  require(control && control.value == lane_value(EndpointRole::control, 1) &&
              broker && broker.value == lane_value(EndpointRole::broker, 1) &&
              render && render.value == lane_value(EndpointRole::render, 1),
          "lane-tagged outbound sequences were not unique");
  require(sequence.accept_inbound(
              EndpointRole::broker, lane_value(EndpointRole::broker, 1)) ==
              FatalReason::none &&
              sequence.accept_inbound(
                  EndpointRole::broker,
                  lane_value(EndpointRole::broker, 3)) == FatalReason::none,
          "lane high-water rejected a permitted counter gap");

  SessionSequence replay;
  require(replay.accept_inbound(
              EndpointRole::render, lane_value(EndpointRole::render, 2)) ==
              FatalReason::none &&
              replay.accept_inbound(
                  EndpointRole::render,
                  lane_value(EndpointRole::render, 2)) ==
                  FatalReason::lane_sequence_replayed &&
              replay.failed(),
          "equal inbound lane sequence was not fatal replay");
  SessionSequence lower;
  require(lower.accept_inbound(
              EndpointRole::control, lane_value(EndpointRole::control, 9)) ==
              FatalReason::none &&
              lower.accept_inbound(
                  EndpointRole::control,
                  lane_value(EndpointRole::control, 8)) ==
                  FatalReason::lane_sequence_replayed,
          "lower inbound lane sequence was not fatal replay");
  SessionSequence zero_sequence;
  require(zero_sequence.accept_inbound(EndpointRole::control, 0) ==
              FatalReason::invalid_lane_sequence,
          "zero inbound lane sequence was accepted");
  SessionSequence wrong_lane;
  require(wrong_lane.accept_inbound(
              EndpointRole::control, lane_value(EndpointRole::broker, 1)) ==
              FatalReason::invalid_lane_sequence,
          "sequence tagged for another lane was accepted");

  SessionSequence maximum(std::numeric_limits<std::uint64_t>::max() >> 2U);
  const auto last = maximum.take_outbound(EndpointRole::render);
  const auto exhausted = maximum.take_outbound(EndpointRole::render);
  require(last && last.value == std::numeric_limits<std::uint64_t>::max() &&
              !exhausted &&
              exhausted.error == FatalReason::lane_sequence_exhausted,
          "outbound session sequence wrapped after UINT64_MAX");
}

void envelope_test() {
  for (const auto role :
       {EndpointRole::control, EndpointRole::broker, EndpointRole::render}) {
    const auto cap = payload_cap(role);
    std::vector<std::byte> payload(cap);
    const auto packet = encode(selected_header(role, kEventType), payload);
    const auto decoded = decode_packet(packet, role);
    require(static_cast<bool>(decoded) && decoded.packet.payload.size() == cap,
            "packet at endpoint cap failed");

    std::vector<std::byte> too_large(cap + 1);
    std::vector<std::byte> output(kHeaderSize + too_large.size());
    require(encode_packet(selected_header(role, kEventType), too_large, output)
                    .error == FatalReason::payload_cap_exceeded,
            "encoder admitted payload above endpoint cap");
  }

  auto packet = encode(selected_header(EndpointRole::control, kEventType));
  auto mutation = packet;
  mutation[0] = std::byte{0};
  require(decode_packet(mutation, EndpointRole::control).error ==
              FatalReason::invalid_magic,
          "bad magic was accepted");
  mutation = packet;
  mutation[14] = std::byte{1};
  require(decode_packet(mutation, EndpointRole::control).error ==
              FatalReason::nonzero_flags,
          "nonzero flags were accepted");
  mutation = packet;
  mutation[20] = std::byte{1};
  require(decode_packet(mutation, EndpointRole::control).error ==
              FatalReason::nonzero_reserved,
          "nonzero reserved field was accepted");
  require(decode_packet(packet, EndpointRole::broker).error ==
              FatalReason::endpoint_role_mismatch,
          "trusted endpoint role was overridden by payload role");
  packet.push_back(std::byte{0});
  require(decode_packet(packet, EndpointRole::control).error ==
              FatalReason::packet_length_mismatch,
          "trailing byte was accepted");
  require(decode_packet(
              std::span<const std::byte>(packet).first(kHeaderSize - 1),
              EndpointRole::control)
                  .error == FatalReason::packet_too_short,
          "short header was accepted");
}

std::vector<std::byte> encode_negotiation(const NegotiationResult &result) {
  return encode(
      result.header,
      std::span<const std::byte>(result.payload).first(result.payload_size));
}

void negotiation_test() {
  RequiredEndpointReadiness readiness;
  for (const auto role :
       {EndpointRole::control, EndpointRole::broker, EndpointRole::render}) {
    WorkerNegotiator worker(role, {1, 2});
    TrustedNegotiator trusted(role, {1, 1}, kGeneration, payload_cap(role), 4);
    const auto worker_hello = worker.make_hello();
    require(worker_hello &&
                worker_hello.header.envelope_version == kEnvelopeVersion &&
                worker_hello.header.header_size == kHeaderSize &&
                worker_hello.header.lane_sequence == 0,
            "worker could not create a canonical HELLO");
    const auto hello_bytes = encode(worker_hello.header, worker_hello.payload);
    const auto hello = decode_packet(hello_bytes, role);
    require(static_cast<bool>(hello), "worker HELLO did not decode");
    const auto reply = trusted.accept_hello(hello.packet);
    require(static_cast<bool>(reply) &&
                reply.kind == NegotiationKind::welcome && trusted.selected(),
            "trusted endpoint did not select highest common version");
    const auto reply_bytes = encode_negotiation(reply);
    const auto decoded_reply = decode_packet(reply_bytes, role);
    require(static_cast<bool>(decoded_reply) &&
                worker.accept_reply(decoded_reply.packet) == FatalReason::none,
            "worker rejected valid WELCOME");
    require(readiness.observe(role, worker.launch_generation()) ==
                FatalReason::none,
            "readiness rejected endpoint");
  }
  bool ready = false;
  require(readiness.ready(ready) == FatalReason::none && ready,
          "three endpoint generations did not become ready");

  WorkerNegotiator duplicate_worker(EndpointRole::control, {1, 1});
  const auto first_hello = duplicate_worker.make_hello();
  require(static_cast<bool>(first_hello) &&
              duplicate_worker.make_hello().error ==
                  FatalReason::invalid_message_order &&
              duplicate_worker.failed(),
          "worker emitted a duplicate HELLO");

  RequiredEndpointReadiness mismatched;
  require(mismatched.observe(EndpointRole::control, kGeneration) ==
                  FatalReason::none &&
              mismatched.observe(EndpointRole::broker, kGeneration) ==
                  FatalReason::none &&
              mismatched.observe(EndpointRole::render, kGeneration + 1) ==
                  FatalReason::none &&
              mismatched.ready(ready) ==
                  FatalReason::readiness_generation_mismatch,
          "mixed generations became ready");

  for (const auto role :
       {EndpointRole::control, EndpointRole::broker, EndpointRole::render}) {
    WorkerNegotiator worker(role, {2, 3});
    TrustedNegotiator trusted(role, {1, 1}, kGeneration, payload_cap(role), 4);
    const auto worker_hello = worker.make_hello();
    require(static_cast<bool>(worker_hello), "worker could not create HELLO");
    const auto hello_bytes = encode(worker_hello.header, worker_hello.payload);
    const auto hello = decode_packet(hello_bytes, role);
    const auto failure = trusted.accept_hello(hello.packet);
    require(failure.kind == NegotiationKind::negotiation_failed &&
                trusted.failed(),
            "no-overlap role negotiation did not fail");
    const auto failure_bytes = encode_negotiation(failure);
    const auto decoded_failure = decode_packet(failure_bytes, role);
    require(worker.accept_reply(decoded_failure.packet) ==
                FatalReason::version_negotiation_failed,
            "worker did not recognize negotiation failure");
  }

}

PacketView decode_selected(const std::vector<std::byte> &bytes,
                           EndpointRole role = EndpointRole::broker) {
  const auto result = decode_packet(bytes, role);
  require(static_cast<bool>(result), "selected packet did not decode");
  return result.packet;
}

void state_test() {
  constexpr std::array rules{
      MessageRule{kRequestType, DirectionMask::bidirectional,
                  CorrelationRule::nonzero, MessageSemantic::request, 0, 8},
      MessageRule{kResponseType, DirectionMask::bidirectional,
                  CorrelationRule::nonzero, MessageSemantic::terminal, 0, 8},
      MessageRule{kEventType, DirectionMask::worker_to_host,
                  CorrelationRule::zero, MessageSemantic::event, 0, 4},
  };
  const std::array schemas{
      RoleSchemaView{EndpointRole::broker, 1, rules, 2, 2},
  };
  const RoleSchemaRegistryView registry(schemas);
  require(registry.validate() == FatalReason::none,
          "test role registry is invalid");

  SelectedEndpointState<4> state(EndpointRole::broker, 1, kGeneration,
                                 payload_cap(EndpointRole::broker), 4,
                                 registry);
  const auto request =
      encode(selected_header(EndpointRole::broker, kRequestType, kCorrelation));
  SelectedEndpointState<4> invalid_direction(
      EndpointRole::broker, 1, kGeneration, payload_cap(EndpointRole::broker),
      4, registry);
  require(invalid_direction
                      .accept(decode_selected(request),
                              static_cast<Direction>(0xff))
                      .error == FatalReason::invalid_direction &&
              invalid_direction.failed(),
          "unknown direction was mapped onto an authoritative channel");
  require(state.accept(decode_selected(request), Direction::worker_to_host)
                  .action == SessionAction::request_admitted,
          "request was not admitted");
  require(state.accept(decode_selected(request), Direction::host_to_worker)
                  .action == SessionAction::request_admitted,
          "same correlation was not independent in opposite direction");

  const auto cancel = encode(selected_header(
      EndpointRole::broker,
      static_cast<std::uint16_t>(CommonMessageType::cancel), kCorrelation));
  require(
      state.accept(decode_selected(cancel), Direction::worker_to_host).action ==
          SessionAction::cancel_requested,
      "cancellation was not correlated");
  require(
      state.accept(decode_selected(request), Direction::worker_to_host).error ==
          FatalReason::correlation_reused,
      "cancelled correlation was reused before terminal result");

  SelectedEndpointState<4> crossed(EndpointRole::broker, 1, kGeneration,
                                   payload_cap(EndpointRole::broker), 4,
                                   registry);
  require(static_cast<bool>(crossed.accept(decode_selected(request),
                                           Direction::worker_to_host)),
          "crossed request failed");
  require(static_cast<bool>(crossed.accept(decode_selected(cancel),
                                           Direction::worker_to_host)),
          "crossed cancel failed");
  const auto response = encode(
      selected_header(EndpointRole::broker, kResponseType, kCorrelation));
  require(crossed.accept(decode_selected(response), Direction::host_to_worker)
                  .action == SessionAction::terminal_received,
          "terminal-before-cancel-result race failed");
  require(crossed.accept(decode_selected(request), Direction::worker_to_host)
                  .error == FatalReason::correlation_reused,
          "crossed operation released correlation too early");

  SelectedEndpointState<4> crossed_complete(
      EndpointRole::broker, 1, kGeneration, payload_cap(EndpointRole::broker),
      4, registry);
  require(
      static_cast<bool>(crossed_complete.accept(decode_selected(request),
                                                Direction::worker_to_host)) &&
          static_cast<bool>(crossed_complete.accept(
              decode_selected(cancel), Direction::worker_to_host)) &&
          crossed_complete
                  .accept(decode_selected(response), Direction::host_to_worker)
                  .action == SessionAction::terminal_received,
      "terminal-first cancellation setup failed");
  const auto late_cancel_result =
      encode(selected_header(
                 EndpointRole::broker,
                 static_cast<std::uint16_t>(CommonMessageType::cancel_result),
                 kCorrelation),
             encode_cancel_result_payload(CancelOutcome::already_completed));
  require(
      crossed_complete
                  .accept(decode_selected(late_cancel_result),
                          Direction::host_to_worker)
                  .action == SessionAction::cancel_result_received &&
          crossed_complete
                  .accept(decode_selected(request), Direction::worker_to_host)
                  .action == SessionAction::request_admitted,
      "late cancel result did not release the completed operation");

  SelectedEndpointState<4> acknowledged(EndpointRole::broker, 1, kGeneration,
                                        payload_cap(EndpointRole::broker), 4,
                                        registry);
  require(static_cast<bool>(acknowledged.accept(decode_selected(request),
                                                Direction::worker_to_host)),
          "acknowledged request failed");
  require(static_cast<bool>(acknowledged.accept(decode_selected(cancel),
                                                Direction::worker_to_host)),
          "acknowledged cancel failed");
  const auto cancel_result =
      encode(selected_header(
                 EndpointRole::broker,
                 static_cast<std::uint16_t>(CommonMessageType::cancel_result),
                 kCorrelation),
             encode_cancel_result_payload(CancelOutcome::accepted));
  require(
      acknowledged
              .accept(decode_selected(cancel_result), Direction::host_to_worker)
              .action == SessionAction::cancel_result_received,
      "cancel result was not correlated");
  require(
      acknowledged.accept(decode_selected(response), Direction::host_to_worker)
              .action == SessionAction::terminal_received,
      "terminal result did not complete acknowledged cancellation");

  SelectedEndpointState<4> typed(EndpointRole::broker, 1, kGeneration,
                                 payload_cap(EndpointRole::broker), 4,
                                 registry);
  require(static_cast<bool>(typed.accept(decode_selected(request),
                                         Direction::worker_to_host)),
          "typed-error request failed");
  const std::array<std::byte, 2> error_payload{std::byte{0}, std::byte{1}};
  const auto typed_error =
      encode(selected_header(
                 EndpointRole::broker,
                 static_cast<std::uint16_t>(CommonMessageType::typed_error),
                 kCorrelation),
             error_payload);
  require(typed.accept(decode_selected(typed_error), Direction::host_to_worker)
                  .action == SessionAction::recoverable_error_received,
          "typed error did not terminate matching operation");

  SelectedEndpointState<1> bounded(EndpointRole::broker, 1, kGeneration,
                                   payload_cap(EndpointRole::broker), 1,
                                   registry);
  require(static_cast<bool>(bounded.accept(decode_selected(request),
                                           Direction::worker_to_host)),
          "bounded first request failed");
  const auto second =
      encode(selected_header(EndpointRole::broker, kRequestType, 2));
  require(bounded.accept(decode_selected(second), Direction::worker_to_host)
                  .error == FatalReason::maximum_in_flight_exceeded,
          "fixed operation table exceeded negotiated bound");

  SelectedEndpointState<4> unknown(EndpointRole::broker, 1, kGeneration,
                                   payload_cap(EndpointRole::broker), 4,
                                   registry);
  const auto unknown_packet =
      encode(selected_header(EndpointRole::broker, 0x1fff, 0));
  require(
      unknown.accept(decode_selected(unknown_packet), Direction::worker_to_host)
              .error == FatalReason::unknown_message_type,
      "unknown role message was accepted");

  SelectedEndpointState<4> narrowed(EndpointRole::broker, 1, kGeneration, 2, 4,
                                    registry);
  const std::array<std::byte, 3> oversized_payload{};
  const auto oversized = encode(
      selected_header(EndpointRole::broker, kEventType), oversized_payload);
  require(narrowed.accept(decode_selected(oversized), Direction::worker_to_host)
                  .error == FatalReason::payload_cap_exceeded,
          "selected state widened the negotiated payload limit");
}

void classification_test() {
  require(classify(Issue::malformed_envelope) == FailureDisposition::fatal &&
              classify(Issue::invalid_state) == FailureDisposition::fatal &&
              classify(Issue::known_operation_denial) ==
                  FailureDisposition::recoverable &&
              classify(Issue::cancellation_outcome) ==
                  FailureDisposition::recoverable,
          "fatal/recoverable classification changed");
}

void canonical_surface_binding_test() {
  const auto first = manifest_surface_binding("bar", 0, 17);
  const auto third = manifest_surface_binding("overlay", 2, 17);
  require(first && first->id == 1 && first->generation == 17 &&
              third && third->id == 3 && third->generation == 17 &&
              !manifest_surface_binding("bar", 0, 0) &&
              !manifest_surface_binding("bad/name", 0, 17) &&
              !manifest_surface_binding("bar", kMaximumPluginSurfaces, 17),
          "canonical manifest surface identity widened or became ambiguous");
}

void permission_snapshot_test() {
  namespace snapshot_wire = omarchy::plugin::wire::permission_snapshot;
  using snapshot_wire::GrantState;
  using snapshot_wire::PermissionRow;
  using snapshot_wire::PermissionSnapshot;

  const PermissionSnapshot source{
      .manifest_request_fingerprint = std::string(64, 'a'),
      .permissions = {{GrantState::granted, 0x0005},
                      {GrantState::denied, 0x0000},
                      {GrantState::revoked, 0xabcd}}};
  const auto golden = snapshot_wire::encode(source);
  require(hex(golden) ==
              "0001616161616161616161616161616161616161616161616161616161616161"
              "6161616161616161616161616161616161616161616161616161616161616161"
              "6161000301000502000003abcd",
          "permission snapshot literal golden mismatch");
  PermissionSnapshot decoded;
  require(snapshot_wire::decode(golden, decoded) && decoded == source,
          "permission snapshot did not round trip exactly");

  const PermissionSnapshot sentinel{.manifest_request_fingerprint =
                                        std::string(64, 'b'),
                                    .permissions = {
                                        {GrantState::revoked, 0x1234}}};
  const auto rejects = [&](std::span<const std::byte> bytes,
                           std::string_view message) {
    auto output = sentinel;
    require(!snapshot_wire::decode(bytes, output) && output == sentinel,
            message);
  };

  for (std::size_t length = 0; length < golden.size(); ++length)
    rejects(std::span(golden).first(length),
            "permission snapshot truncation was accepted");

  auto malformed = golden;
  malformed[1] = std::byte{2};
  rejects(malformed, "unknown permission snapshot codec was accepted");
  malformed = golden;
  malformed[2] = std::byte{'A'};
  rejects(malformed,
          "noncanonical permission snapshot fingerprint was accepted");
  malformed = golden;
  malformed[2] = std::byte{'g'};
  rejects(malformed, "invalid permission snapshot fingerprint was accepted");
  malformed = golden;
  malformed[66] = std::byte{1};
  malformed[67] = std::byte{1};
  rejects(malformed, "oversized permission request count was accepted");
  malformed = golden;
  malformed[67] = std::byte{2};
  rejects(malformed, "permission snapshot trailing byte was accepted");
  malformed = golden;
  malformed.push_back(std::byte{1});
  rejects(malformed, "permission snapshot suffix was accepted");
  malformed = golden;
  malformed[73] = std::byte{1};
  rejects(malformed, "denied permission row retained operation bits");
  malformed = golden;
  malformed[69] = std::byte{0};
  malformed[70] = std::byte{0};
  rejects(malformed, "empty granted permission row was accepted");
  malformed = golden;
  malformed[75] = std::byte{0};
  malformed[76] = std::byte{0};
  rejects(malformed, "empty revoked permission row was accepted");

  for (unsigned int value = 0; value <= 0xff; ++value) {
    malformed = golden;
    malformed[68] = static_cast<std::byte>(value);
    if (value == static_cast<unsigned int>(GrantState::denied)) {
      malformed[69] = std::byte{0};
      malformed[70] = std::byte{0};
    }
    auto state = sentinel;
    const bool accepted = snapshot_wire::decode(malformed, state);
    const bool valid =
        value >= static_cast<unsigned int>(GrantState::granted) &&
        value <= static_cast<unsigned int>(GrantState::revoked);
    require(accepted == valid &&
                (valid ? snapshot_wire::encode(state) == malformed
                       : state == sentinel),
            "permission snapshot grant state validation changed");
  }

  PermissionSnapshot empty{.manifest_request_fingerprint = std::string(64, '0'),
                           .permissions = {}};
  const auto empty_encoded = snapshot_wire::encode(empty);
  require(empty_encoded.size() == snapshot_wire::kFixedPayloadBytes &&
              snapshot_wire::decode(empty_encoded, decoded) && decoded == empty,
          "empty permission snapshot did not round trip");

  PermissionSnapshot maximum{
      .manifest_request_fingerprint = std::string(64, 'f'),
      .permissions = std::vector<PermissionRow>(
          snapshot_wire::kMaximumManifestRequests,
          {GrantState::denied, 0})};
  const auto maximum_encoded = snapshot_wire::encode(maximum);
  require(maximum_encoded.size() == snapshot_wire::kMaximumPayloadBytes &&
              snapshot_wire::decode(maximum_encoded, decoded) &&
              decoded == maximum,
          "maximum permission snapshot did not round trip");
  maximum.permissions.push_back({GrantState::denied, 0});
  require(snapshot_wire::encode(maximum).empty(),
          "encoder exceeded the manifest request bound");
  auto too_large = maximum_encoded;
  too_large.push_back(std::byte{0});
  rejects(too_large, "decoder exceeded the manifest request bound");

  auto invalid_source = source;
  invalid_source.manifest_request_fingerprint[0] = 'A';
  require(snapshot_wire::encode(invalid_source).empty(),
          "encoder accepted a noncanonical fingerprint");
  invalid_source = source;
  invalid_source.permissions[0].state = static_cast<GrantState>(0);
  require(snapshot_wire::encode(invalid_source).empty(),
          "encoder accepted an invalid grant state");
  invalid_source = source;
  invalid_source.permissions[1].operation_mask = 1;
  require(snapshot_wire::encode(invalid_source).empty(),
          "encoder accepted operation bits on a denied row");
  invalid_source = source;
  invalid_source.permissions[0].operation_mask = 0;
  require(snapshot_wire::encode(invalid_source).empty(),
          "encoder accepted an empty granted row");
  invalid_source = source;
  invalid_source.permissions[2].operation_mask = 0;
  require(snapshot_wire::encode(invalid_source).empty(),
          "encoder accepted an empty revoked row");

  const auto verifies = [&](std::span<const std::byte> bytes,
                            bool expected_valid, std::string_view message) {
    auto output = sentinel;
    const bool accepted = snapshot_wire::decode(bytes, output);
    require(accepted == expected_valid &&
                (accepted
                     ? std::ranges::equal(snapshot_wire::encode(output), bytes)
                     : output == sentinel),
            message);
  };

  std::uint32_t random = 0x6f6d6172U;
  for (std::size_t iteration = 0; iteration < 4096; ++iteration) {
    random = random * 1664525U + 1013904223U;
    auto bytes = golden;
    switch (iteration % 8) {
    case 0:
      bytes[1] = static_cast<std::byte>((random % 0xfeU) + 2U);
      verifies(bytes, false, "mutated codec version was accepted");
      break;
    case 1: {
      constexpr std::string_view digits = "0123456789abcdef";
      bytes[2 + (random % snapshot_wire::kManifestRequestFingerprintBytes)] =
          static_cast<std::byte>(digits[random % digits.size()]);
      verifies(bytes, true,
               "canonical fingerprint mutation did not round trip");
      break;
    }
    case 2:
      bytes[2 + (random % snapshot_wire::kManifestRequestFingerprintBytes)] =
          std::byte{'G'};
      verifies(bytes, false, "invalid fingerprint mutation was accepted");
      break;
    case 3: {
      const auto count = static_cast<std::uint16_t>(
          random % (snapshot_wire::kMaximumManifestRequests + 1));
      bytes.resize(snapshot_wire::kFixedPayloadBytes +
                   count * snapshot_wire::kPermissionRowBytes);
      bytes[66] = static_cast<std::byte>(count >> 8U);
      bytes[67] = static_cast<std::byte>(count);
      for (std::size_t index = 0; index < count; ++index) {
        random = random * 1664525U + 1013904223U;
        const auto offset = snapshot_wire::kFixedPayloadBytes +
                            index * snapshot_wire::kPermissionRowBytes;
        const auto state = (random % 3U) + 1U;
        bytes[offset] = static_cast<std::byte>(state);
        std::uint16_t mask = static_cast<std::uint16_t>(random);
        if (state == 2U)
          mask = 0;
        else if (mask == 0)
          mask = 1;
        bytes[offset + 1] = static_cast<std::byte>(mask >> 8U);
        bytes[offset + 2] = static_cast<std::byte>(mask);
      }
      verifies(bytes, true, "bounded count mutation did not round trip");
      break;
    }
    case 4: {
      const auto count = static_cast<std::uint16_t>(
          random % (snapshot_wire::kMaximumManifestRequests + 1));
      bytes[66] = static_cast<std::byte>(count >> 8U);
      bytes[67] = static_cast<std::byte>(count);
      const auto exact = snapshot_wire::kFixedPayloadBytes +
                         count * snapshot_wire::kPermissionRowBytes;
      bytes.resize(exact == snapshot_wire::kMaximumPayloadBytes ? exact - 1
                                                                : exact + 1,
                   std::byte{1});
      verifies(bytes, false, "mismatched count mutation was accepted");
      break;
    }
    case 5: {
      const auto count = static_cast<std::uint16_t>((random % 256U) + 1U);
      bytes.resize(snapshot_wire::kFixedPayloadBytes +
                       count * snapshot_wire::kPermissionRowBytes,
                   std::byte{1});
      bytes[66] = static_cast<std::byte>(count >> 8U);
      bytes[67] = static_cast<std::byte>(count);
      random = random * 1664525U + 1013904223U;
      bytes[snapshot_wire::kFixedPayloadBytes +
            (random % count) * snapshot_wire::kPermissionRowBytes] =
          static_cast<std::byte>((random & 1U) == 0 ? 0U : 0xffU);
      verifies(bytes, false, "invalid state mutation was accepted");
      break;
    }
    case 6:
      bytes.resize(random % golden.size());
      verifies(bytes, false, "structured truncation was accepted");
      break;
    case 7:
      bytes.resize(golden.size() + (random % 16U) + 1U, std::byte{1});
      verifies(bytes, false, "structured suffix was accepted");
      break;
    }
  }
}

} // namespace

int main() {
  try {
    golden_test();
    envelope_and_sequence_test();
    envelope_test();
    negotiation_test();
    state_test();
    classification_test();
    canonical_surface_binding_test();
    permission_snapshot_test();
    std::cout << "plugin wire contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin wire contract: " << error.what() << '\n';
    return 1;
  }
}
