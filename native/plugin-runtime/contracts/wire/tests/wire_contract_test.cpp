#include "omarchy/plugin/wire/common.hpp"
#include "omarchy/plugin/wire/control.hpp"
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
  std::vector<std::byte> output(header_size(header.envelope_version) +
                                payload.size());
  const auto result = encode_packet(header, payload, output);
  require(static_cast<bool>(result) && result.bytes_written == output.size(),
          "packet encoding failed");
  return output;
}

EnvelopeHeader v2_header(EndpointRole role, std::uint16_t type,
                         std::uint64_t sequence,
                         std::uint64_t correlation = 0) {
  return {.envelope_version = kEnvelopeVersionV2,
          .header_size = kHeaderSizeV2,
          .endpoint_role = role,
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
                        .correlation_id = correlation};
}

void golden_test() {
  const auto hello_payload =
      encode_hello_payload(HelloPayload{VersionRange{1, 1}});
  const auto hello = encode(
      EnvelopeHeader{.endpoint_role = EndpointRole::control}, hello_payload);
  require(hex(hello) ==
              "4f4d504c00010028000100010000000000000004000000000000000000000000"
              "000000000000000000010001",
          "HELLO literal golden mismatch");

  const auto welcome_payload = encode_welcome_payload({4096, 4});
  const auto welcome = encode(
      selected_header(EndpointRole::control,
                      static_cast<std::uint16_t>(CommonMessageType::welcome)),
      welcome_payload);
  require(hex(welcome) ==
              "4f4d504c00010028000100020001000000000008000000000102030405060708"
              "00000000000000000000100000000004",
          "WELCOME literal golden mismatch");

  const auto failed_payload = encode_negotiation_failed_payload(
      {NegotiationFailure::no_common_role_version, {1, 1}});
  const auto failed =
      encode(EnvelopeHeader{.endpoint_role = EndpointRole::render,
                            .message_type = static_cast<std::uint16_t>(
                                CommonMessageType::negotiation_failed)},
             failed_payload);
  require(hex(failed) ==
              "4f4d504c00010028000300030000000000000006000000000000000000000000"
              "0000000000000000000100010001",
          "NEGOTIATION_FAILED literal golden mismatch");

  const std::array<std::byte, 2> reason{std::byte{0}, std::byte{1}};
  const auto typed = encode(selected_header(EndpointRole::broker,
                                            static_cast<std::uint16_t>(
                                                CommonMessageType::typed_error),
                                            kCorrelation),
                            reason);
  require(hex(typed) ==
              "4f4d504c00010028000200040001000000000002000000000102030405060708"
              "11121314151617180001",
          "TYPED_ERROR literal golden mismatch");

  const auto cancel = encode(selected_header(
      EndpointRole::broker,
      static_cast<std::uint16_t>(CommonMessageType::cancel), kCorrelation));
  require(hex(cancel) ==
              "4f4d504c00010028000200050001000000000000000000000102030405060708"
              "1112131415161718",
          "CANCEL literal golden mismatch");

  const auto cancel_result =
      encode(selected_header(
                 EndpointRole::broker,
                 static_cast<std::uint16_t>(CommonMessageType::cancel_result),
                 kCorrelation),
             encode_cancel_result_payload(CancelOutcome::accepted));
  require(hex(cancel_result) ==
              "4f4d504c00010028000200060001000000000002000000000102030405060708"
              "11121314151617180001",
          "CANCEL_RESULT literal golden mismatch");

  const auto protocol_error = encode(
      selected_header(
          EndpointRole::broker,
          static_cast<std::uint16_t>(CommonMessageType::protocol_error)),
      encode_protocol_error_payload(ProtocolErrorReason::invalid_message));
  require(hex(protocol_error) ==
              "4f4d504c00010028000200070001000000000002000000000102030405060708"
              "00000000000000000001",
          "PROTOCOL_ERROR literal golden mismatch");

  const std::array<std::byte, 2> v2_payload{std::byte{0xaa}, std::byte{0x55}};
  const auto v2 = encode(v2_header(EndpointRole::broker, kRequestType,
                                   0x212223242526272aULL, kCorrelation),
                         v2_payload);
  require(
      hex(v2) ==
          "4f4d504c00020030000211000001000000000002000000000102030405060708"
          "1112131415161718212223242526272aaa55",
      "v2 literal golden or sequence offset mismatch");
}

void v2_envelope_and_sequence_test() {
  static_assert(!std::is_copy_constructible_v<SessionSequence>);
  static_assert(!std::is_move_constructible_v<SessionSequence>);
  const auto valid = encode(v2_header(
      EndpointRole::broker, kRequestType,
      lane_value(EndpointRole::broker, 1), kCorrelation));
  const auto decoded = decode_packet(valid, EndpointRole::broker);
  require(decoded && decoded.packet.header.envelope_version ==
                         kEnvelopeVersionV2 &&
              decoded.packet.header.header_size == kHeaderSizeV2 &&
              decoded.packet.header.lane_sequence ==
                  lane_value(EndpointRole::broker, 1),
          "v2 envelope did not decode exactly");

  auto crossed = v2_header(EndpointRole::broker, kRequestType,
                           lane_value(EndpointRole::broker, 1), kCorrelation);
  crossed.header_size = kHeaderSizeV1;
  std::array<std::byte, kHeaderSizeV2> output{};
  require(encode_packet(crossed, {}, output).error ==
              FatalReason::invalid_header_size,
          "v2 envelope accepted the v1 header size");
  auto crossed_bytes = valid;
  crossed_bytes[6] = std::byte{0};
  crossed_bytes[7] = std::byte{static_cast<unsigned char>(kHeaderSizeV1)};
  require(decode_packet(crossed_bytes, EndpointRole::broker).error ==
              FatalReason::invalid_header_size,
          "decoder accepted the v1 header size on a v2 packet");
  auto legacy = selected_header(EndpointRole::broker, kRequestType,
                                kCorrelation);
  legacy.header_size = kHeaderSizeV2;
  require(encode_packet(legacy, {}, output).error ==
              FatalReason::invalid_header_size,
          "v1 envelope accepted the v2 header size");
  legacy = selected_header(EndpointRole::broker, kRequestType, kCorrelation);
  legacy.lane_sequence = 1;
  require(encode_packet(legacy, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "v1 envelope silently encoded a v2 sequence");

  auto zero = v2_header(EndpointRole::broker, kRequestType, 0, kCorrelation);
  require(encode_packet(zero, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "v2 post-ready packet accepted sequence zero");
  auto wrong_tag = v2_header(EndpointRole::control, kRequestType,
                             lane_value(EndpointRole::broker, 1), kCorrelation);
  require(encode_packet(wrong_tag, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "v2 envelope accepted a sequence tagged for another lane");
  auto sequenced_hello = v2_header(
      EndpointRole::control,
      static_cast<std::uint16_t>(CommonMessageType::hello), 1);
  sequenced_hello.role_protocol_version = 0;
  sequenced_hello.launch_generation = 0;
  require(encode_packet(sequenced_hello, {}, output).error ==
              FatalReason::invalid_lane_sequence,
          "v2 HELLO accepted a nonzero sequence");

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
  require(decode_packet(std::span<const std::byte>(packet).first(39),
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
    require(static_cast<bool>(worker_hello), "worker could not create HELLO");
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

  WorkerNegotiator v2_worker(EndpointRole::control, {1, 1},
                             kEnvelopeVersionV2);
  TrustedNegotiator v2_trusted(EndpointRole::control, {1, 1}, kGeneration,
                               payload_cap(EndpointRole::control), 4,
                               kEnvelopeVersionV2);
  const auto v2_hello = v2_worker.make_hello();
  require(v2_hello && v2_hello.header.header_size == kHeaderSizeV2 &&
              v2_hello.header.lane_sequence == 0,
          "v2 worker did not emit a canonical HELLO");
  const auto v2_hello_bytes = encode(v2_hello.header, v2_hello.payload);
  const auto decoded_v2_hello =
      decode_packet(v2_hello_bytes, EndpointRole::control);
  const auto v2_welcome = v2_trusted.accept_hello(decoded_v2_hello.packet);
  require(v2_welcome && v2_welcome.header.envelope_version ==
                            kEnvelopeVersionV2 &&
              v2_welcome.header.lane_sequence == 0,
          "v2 trusted endpoint did not emit a canonical WELCOME");
  WorkerNegotiator v1_worker(EndpointRole::control, {1, 1});
  const auto v1_hello = v1_worker.make_hello();
  const auto v1_hello_bytes = encode(v1_hello.header, v1_hello.payload);
  const auto decoded_v1_hello =
      decode_packet(v1_hello_bytes, EndpointRole::control);
  TrustedNegotiator disjoint(EndpointRole::control, {1, 1}, kGeneration,
                             payload_cap(EndpointRole::control), 4,
                             kEnvelopeVersionV2);
  require(disjoint.accept_hello(decoded_v1_hello.packet).error ==
              FatalReason::invalid_message_order,
          "v2 negotiator accepted a v1 HELLO");
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

void surface_binding_test() {
  const SurfaceBinding binding{
      .id = 0x0102030405060708ULL,
      .generation = 17,
      .surface = "barWidget"};
  const auto encoded = encode_surface_binding(binding);
  SurfaceBinding decoded;
  require(!encoded.empty() && decode_surface_binding(encoded, decoded) &&
              decoded.id == binding.id &&
              decoded.generation == binding.generation &&
              decoded.surface == binding.surface,
          "surface binding did not round trip exactly");
  auto malformed = encoded;
  malformed[16] = std::byte{64};
  require(!decode_surface_binding(malformed, decoded),
          "malformed surface binding length was accepted");
  malformed = encoded;
  malformed.back() = std::byte{'/'};
  require(!decode_surface_binding(malformed, decoded) &&
              encode_surface_binding({}).empty(),
          "unsafe or empty surface binding was accepted");
}

} // namespace

int main() {
  try {
    golden_test();
    v2_envelope_and_sequence_test();
    envelope_test();
    negotiation_test();
    state_test();
    classification_test();
    surface_binding_test();
    std::cout << "plugin wire contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin wire contract: " << error.what() << '\n';
    return 1;
  }
}
