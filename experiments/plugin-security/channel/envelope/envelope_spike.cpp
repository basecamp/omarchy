#include <arpa/inet.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f4d504c;
constexpr std::uint16_t kEnvelopeVersion = 1;
constexpr std::uint16_t kHeaderSize = 40;
constexpr std::uint16_t kRoleVersion = 1;
constexpr std::uint64_t kGeneration = 0x0102030405060708ULL;
constexpr std::uint32_t kMaxInFlight = 4;

enum class Role : std::uint16_t { control = 1, broker = 2, render = 3 };
enum class Direction { worker_to_host, host_to_worker };
enum class Type : std::uint16_t {
  hello = 0x0001,
  welcome = 0x0002,
  negotiation_failed = 0x0003,
  typed_error = 0x0004,
  cancel = 0x0005,
  cancel_result = 0x0006,
  protocol_error = 0x0007,
  request = 0x0100,
  response = 0x0101,
  render_buffer = 0x0102,
};

struct Header {
  std::uint32_t magic = kMagic;
  std::uint16_t envelope_version = kEnvelopeVersion;
  std::uint16_t header_size = kHeaderSize;
  Role role = Role::control;
  Type type = Type::hello;
  std::uint16_t role_version = 0;
  std::uint16_t flags = 0;
  std::uint32_t payload_length = 0;
  std::uint32_t reserved = 0;
  std::uint64_t generation = 0;
  std::uint64_t correlation = 0;
};

struct Packet {
  Header header;
  std::vector<std::byte> payload;
};

class FatalError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

void require(bool condition, std::string_view message) {
  if (!condition) {
    throw std::runtime_error(std::string(message));
  }
}

std::uint32_t payload_cap(Role role) {
  switch (role) {
  case Role::control:
    return 4096;
  case Role::broker:
    return 65536;
  case Role::render:
    return 16384;
  }
  throw FatalError("unknown endpoint role");
}

void put16(std::span<std::byte> out, std::size_t offset, std::uint16_t value) {
  value = htons(value);
  std::memcpy(out.data() + offset, &value, sizeof(value));
}

void put32(std::span<std::byte> out, std::size_t offset, std::uint32_t value) {
  value = htonl(value);
  std::memcpy(out.data() + offset, &value, sizeof(value));
}

void put64(std::span<std::byte> out, std::size_t offset, std::uint64_t value) {
  const std::uint32_t high = static_cast<std::uint32_t>(value >> 32U);
  const std::uint32_t low = static_cast<std::uint32_t>(value);
  put32(out, offset, high);
  put32(out, offset + 4, low);
}

std::uint16_t get16(std::span<const std::byte> in, std::size_t offset) {
  std::uint16_t value;
  std::memcpy(&value, in.data() + offset, sizeof(value));
  return ntohs(value);
}

std::uint32_t get32(std::span<const std::byte> in, std::size_t offset) {
  std::uint32_t value;
  std::memcpy(&value, in.data() + offset, sizeof(value));
  return ntohl(value);
}

std::uint64_t get64(std::span<const std::byte> in, std::size_t offset) {
  return (static_cast<std::uint64_t>(get32(in, offset)) << 32U) |
         get32(in, offset + 4);
}

std::vector<std::byte> encode(Header header,
                              std::span<const std::byte> payload = {}) {
  if (payload.size() > std::numeric_limits<std::uint32_t>::max()) {
    throw std::runtime_error("payload cannot be represented");
  }
  header.payload_length = static_cast<std::uint32_t>(payload.size());
  std::vector<std::byte> bytes(kHeaderSize + payload.size());
  put32(bytes, 0, header.magic);
  put16(bytes, 4, header.envelope_version);
  put16(bytes, 6, header.header_size);
  put16(bytes, 8, static_cast<std::uint16_t>(header.role));
  put16(bytes, 10, static_cast<std::uint16_t>(header.type));
  put16(bytes, 12, header.role_version);
  put16(bytes, 14, header.flags);
  put32(bytes, 16, header.payload_length);
  put32(bytes, 20, header.reserved);
  put64(bytes, 24, header.generation);
  put64(bytes, 32, header.correlation);
  std::memcpy(bytes.data() + kHeaderSize, payload.data(), payload.size());
  return bytes;
}

Packet decode(std::span<const std::byte> bytes, Role expected_role) {
  if (bytes.size() < kHeaderSize) {
    throw FatalError("packet shorter than envelope header");
  }

  Header header{.magic = get32(bytes, 0),
                .envelope_version = get16(bytes, 4),
                .header_size = get16(bytes, 6),
                .role = static_cast<Role>(get16(bytes, 8)),
                .type = static_cast<Type>(get16(bytes, 10)),
                .role_version = get16(bytes, 12),
                .flags = get16(bytes, 14),
                .payload_length = get32(bytes, 16),
                .reserved = get32(bytes, 20),
                .generation = get64(bytes, 24),
                .correlation = get64(bytes, 32)};

  if (header.magic != kMagic || header.envelope_version != kEnvelopeVersion ||
      header.header_size != kHeaderSize) {
    throw FatalError("unsupported envelope framing");
  }
  if (header.flags != 0 || header.reserved != 0) {
    throw FatalError("nonzero envelope flags or reserved field");
  }
  if (header.role != expected_role) {
    throw FatalError("endpoint role mismatch");
  }
  if (header.payload_length > payload_cap(expected_role)) {
    throw FatalError("endpoint payload cap exceeded");
  }
  if (bytes.size() != kHeaderSize + header.payload_length) {
    throw FatalError("packet length mismatch");
  }

  return Packet{.header = header,
                .payload = std::vector<std::byte>(bytes.begin() + kHeaderSize,
                                                  bytes.end())};
}

std::array<std::byte, 4> hello_payload(std::uint16_t minimum,
                                       std::uint16_t maximum) {
  std::array<std::byte, 4> payload{};
  put16(payload, 0, minimum);
  put16(payload, 2, maximum);
  return payload;
}

std::array<std::byte, 8> welcome_payload(std::uint32_t maximum_payload,
                                         std::uint32_t maximum_in_flight) {
  std::array<std::byte, 8> payload{};
  put32(payload, 0, maximum_payload);
  put32(payload, 4, maximum_in_flight);
  return payload;
}

class EndpointMachine {
public:
  explicit EndpointMachine(Role role) : role_(role) {}

  std::vector<std::byte> accept_hello(std::span<const std::byte> bytes) {
    if (selected_ || hello_seen_) {
      throw FatalError("duplicate HELLO");
    }
    const auto packet = decode(bytes, role_);
    if (packet.header.type != Type::hello || packet.header.role_version != 0 ||
        packet.header.generation != 0 || packet.header.correlation != 0 ||
        packet.payload.size() != 4) {
      throw FatalError("invalid HELLO state");
    }
    hello_seen_ = true;
    const auto minimum = get16(packet.payload, 0);
    const auto maximum = get16(packet.payload, 2);
    if (minimum == 0 || minimum > maximum) {
      throw FatalError("invalid HELLO version range");
    }
    if (minimum > kRoleVersion || maximum < kRoleVersion) {
      Header failed{.role = role_, .type = Type::negotiation_failed};
      std::array<std::byte, 6> payload{};
      put16(payload, 0, 1);
      put16(payload, 2, kRoleVersion);
      put16(payload, 4, kRoleVersion);
      return encode(failed, payload);
    }

    selected_ = true;
    Header welcome{.role = role_,
                   .type = Type::welcome,
                   .role_version = kRoleVersion,
                   .generation = kGeneration};
    const auto payload = welcome_payload(payload_cap(role_), kMaxInFlight);
    return encode(welcome, payload);
  }

  std::optional<std::vector<std::byte>>
  accept_selected(std::span<const std::byte> bytes, Direction direction) {
    if (!selected_) {
      throw FatalError("message before WELCOME");
    }
    const auto packet = decode(bytes, role_);
    if (packet.header.role_version != kRoleVersion ||
        packet.header.generation != kGeneration) {
      throw FatalError("stale generation or role version");
    }

    switch (packet.header.type) {
    case Type::request:
      if (packet.header.correlation == 0 ||
          operations(direction).contains(packet.header.correlation) ||
          operations(direction).size() >= kMaxInFlight) {
        throw FatalError("illegal request correlation");
      }
      operations(direction).emplace(packet.header.correlation, Operation{});
      if (!packet.payload.empty() &&
          packet.payload.front() == std::byte{0xff}) {
        operations(direction).erase(packet.header.correlation);
        Header error{.role = role_,
                     .type = Type::typed_error,
                     .role_version = kRoleVersion,
                     .generation = kGeneration,
                     .correlation = packet.header.correlation};
        const std::array<std::byte, 2> reason{std::byte{0}, std::byte{1}};
        return encode(error, reason);
      }
      return std::nullopt;
    case Type::cancel: {
      if (packet.header.correlation == 0 || !packet.payload.empty()) {
        throw FatalError("invalid CANCEL correlation or payload");
      }
      auto operation = operations(direction).find(packet.header.correlation);
      const bool existed = operation != operations(direction).end();
      if (existed) {
        operation->second.cancel_requested = true;
      }
      Header result{.role = role_,
                    .type = Type::cancel_result,
                    .role_version = kRoleVersion,
                    .generation = kGeneration,
                    .correlation = packet.header.correlation};
      std::array<std::byte, 2> outcome{};
      put16(outcome, 0, existed ? 1 : 3);
      return encode(result, outcome);
    }
    case Type::cancel_result: {
      if (packet.header.correlation == 0 || packet.payload.size() != 2) {
        throw FatalError("invalid CANCEL_RESULT");
      }
      auto &initiated = operations(opposite(direction));
      const auto operation = initiated.find(packet.header.correlation);
      const auto outcome = get16(packet.payload, 0);
      if (operation == initiated.end() || !operation->second.cancel_requested ||
          operation->second.cancel_acknowledged || outcome < 1 || outcome > 4) {
        throw FatalError("unmatched CANCEL_RESULT");
      }
      operation->second.cancel_acknowledged = true;
      if (operation->second.terminal_received) {
        initiated.erase(operation);
      }
      return std::nullopt;
    }
    case Type::response:
    case Type::typed_error: {
      if (packet.header.correlation == 0 ||
          (packet.header.type == Type::typed_error &&
           packet.payload.size() != 2)) {
        throw FatalError("invalid terminal result");
      }
      auto &initiated = operations(opposite(direction));
      const auto operation = initiated.find(packet.header.correlation);
      if (operation == initiated.end() || operation->second.terminal_received) {
        throw FatalError("unmatched or duplicate terminal result");
      }
      if (operation->second.cancel_requested &&
          !operation->second.cancel_acknowledged) {
        operation->second.terminal_received = true;
      } else {
        initiated.erase(operation);
      }
      return std::nullopt;
    }
    default:
      throw FatalError("unknown or illegal selected-state message type");
    }
  }

  [[nodiscard]] bool selected() const { return selected_; }

private:
  struct Operation {
    bool cancel_requested = false;
    bool cancel_acknowledged = false;
    bool terminal_received = false;
  };

  static Direction opposite(Direction direction) {
    return direction == Direction::worker_to_host ? Direction::host_to_worker
                                                  : Direction::worker_to_host;
  }

  std::map<std::uint64_t, Operation> &operations(Direction direction) {
    return direction == Direction::worker_to_host ? worker_operations_
                                                  : host_operations_;
  }

  Role role_;
  bool hello_seen_ = false;
  bool selected_ = false;
  std::map<std::uint64_t, Operation> worker_operations_;
  std::map<std::uint64_t, Operation> host_operations_;
};

class WorkerEndpointMachine {
public:
  explicit WorkerEndpointMachine(Role role) : role_(role) {}

  std::vector<std::byte> make_hello(std::uint16_t minimum = 1,
                                    std::uint16_t maximum = 1) {
    if (hello_sent_ || minimum == 0 || minimum > maximum) {
      throw FatalError("invalid worker HELLO state");
    }
    hello_sent_ = true;
    minimum_ = minimum;
    maximum_ = maximum;
    return encode(Header{.role = role_, .type = Type::hello},
                  hello_payload(minimum, maximum));
  }

  std::uint64_t accept_welcome(std::span<const std::byte> bytes) {
    if (!hello_sent_ || selected_) {
      throw FatalError("WELCOME in invalid worker state");
    }
    const auto packet = decode(bytes, role_);
    if (packet.header.type != Type::welcome ||
        packet.header.role_version < minimum_ ||
        packet.header.role_version > maximum_ ||
        packet.header.generation == 0 || packet.header.correlation != 0 ||
        packet.payload.size() != 8) {
      throw FatalError("invalid WELCOME");
    }
    const auto maximum_payload = get32(packet.payload, 0);
    const auto maximum_in_flight = get32(packet.payload, 4);
    if (maximum_payload == 0 || maximum_payload > payload_cap(role_) ||
        maximum_in_flight == 0) {
      throw FatalError("invalid WELCOME bounds");
    }
    selected_ = true;
    return packet.header.generation;
  }

private:
  Role role_;
  bool hello_sent_ = false;
  bool selected_ = false;
  std::uint16_t minimum_ = 0;
  std::uint16_t maximum_ = 0;
};

class ReadinessGate {
public:
  void observe(Role role, std::uint64_t generation) {
    if (generation == 0 || generations_.contains(role)) {
      throw FatalError("invalid or duplicate endpoint readiness");
    }
    generations_.emplace(role, generation);
  }

  [[nodiscard]] bool ready() const {
    if (generations_.size() != 3) {
      return false;
    }
    const auto generation = generations_.begin()->second;
    for (const auto &[role, observed] : generations_) {
      (void)role;
      if (observed != generation) {
        throw FatalError("endpoint launch generations disagree");
      }
    }
    return true;
  }

private:
  std::map<Role, std::uint64_t> generations_;
};

struct PeerCredentials {
  pid_t pid;
  uid_t uid;
  gid_t gid;
};

struct LaunchBinding {
  PeerCredentials worker;
  int pidfd;
};

template <typename PidfdCheck>
void validate_daemon_peer(const PeerCredentials &actual,
                          const LaunchBinding &binding,
                          PidfdCheck pidfd_check) {
  if (actual.pid != binding.worker.pid || actual.uid != binding.worker.uid ||
      actual.gid != binding.worker.gid || !pidfd_check(binding.pidfd)) {
    throw FatalError("worker credentials do not match pidfd launch binding");
  }
}

void validate_worker_peer(const PeerCredentials &baseline,
                          const PeerCredentials &actual) {
  const bool pid_matches =
      baseline.pid == 0 ? actual.pid == 0 : actual.pid == baseline.pid;
  if (!pid_matches || actual.uid != baseline.uid ||
      actual.gid != baseline.gid) {
    throw FatalError("daemon credentials differ from translated baseline");
  }
}

template <typename Callback>
void require_fatal(Callback callback, std::string_view description) {
  bool fatal = false;
  try {
    callback();
  } catch (const FatalError &) {
    fatal = true;
  }
  require(fatal, description);
}

std::string packet_hex(std::span<const std::byte> packet) {
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (const auto value : packet) {
    output << std::setw(2) << std::to_integer<unsigned int>(value);
  }
  return output.str();
}

void golden_header_test() {
  Header hello{.role = Role::control, .type = Type::hello};
  const auto encoded = encode(hello, hello_payload(1, 1));
  constexpr std::array<std::byte, 44> golden = {
      std::byte{0x4f}, std::byte{0x4d}, std::byte{0x50}, std::byte{0x4c},
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x28},
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x01},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x04},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x01}};
  require(encoded.size() == golden.size() &&
              std::equal(golden.begin(), golden.end(), encoded.begin()),
          "exact HELLO golden packet mismatch");

  const auto cancel = encode(Header{.role = Role::broker,
                                    .type = Type::cancel,
                                    .role_version = kRoleVersion,
                                    .generation = kGeneration,
                                    .correlation = 0x1112131415161718ULL});
  constexpr std::array<std::byte, 40> cancel_golden = {
      std::byte{0x4f}, std::byte{0x4d}, std::byte{0x50}, std::byte{0x4c},
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x28},
      std::byte{0x00}, std::byte{0x02}, std::byte{0x00}, std::byte{0x05},
      std::byte{0x00}, std::byte{0x01}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x00}, std::byte{0x00}, std::byte{0x00}, std::byte{0x00},
      std::byte{0x01}, std::byte{0x02}, std::byte{0x03}, std::byte{0x04},
      std::byte{0x05}, std::byte{0x06}, std::byte{0x07}, std::byte{0x08},
      std::byte{0x11}, std::byte{0x12}, std::byte{0x13}, std::byte{0x14},
      std::byte{0x15}, std::byte{0x16}, std::byte{0x17}, std::byte{0x18}};
  require(cancel.size() == cancel_golden.size() &&
              std::equal(cancel_golden.begin(), cancel_golden.end(),
                         cancel.begin()),
          "exact selected CANCEL golden packet mismatch");

  const auto common_packet = [](Type type, std::span<const std::byte> payload,
                                std::uint64_t correlation = 0) {
    return encode(Header{.role = Role::broker,
                         .type = type,
                         .role_version = kRoleVersion,
                         .generation = kGeneration,
                         .correlation = correlation},
                  payload);
  };
  const auto welcome = encode(Header{.role = Role::control,
                                     .type = Type::welcome,
                                     .role_version = kRoleVersion,
                                     .generation = kGeneration},
                              welcome_payload(4096, 4));
  require(packet_hex(welcome) ==
              "4f4d504c00010028000100020001000000000008000000000102030405060708"
              "00000000000000000000100000000004",
          "exact WELCOME golden packet mismatch");

  std::array<std::byte, 6> failed_payload{};
  put16(failed_payload, 0, 1);
  put16(failed_payload, 2, 1);
  put16(failed_payload, 4, 1);
  const auto failed =
      encode(Header{.role = Role::render, .type = Type::negotiation_failed},
             failed_payload);
  require(packet_hex(failed) ==
              "4f4d504c00010028000300030000000000000006000000000000000000000000"
              "0000000000000000000100010001",
          "exact NEGOTIATION_FAILED golden packet mismatch");

  const std::array<std::byte, 2> outcome{std::byte{0}, std::byte{1}};
  require(packet_hex(common_packet(Type::typed_error, outcome,
                                   0x1112131415161718ULL)) ==
              "4f4d504c00010028000200040001000000000002000000000102030405060708"
              "11121314151617180001",
          "exact TYPED_ERROR golden packet mismatch");
  require(packet_hex(common_packet(Type::cancel_result, outcome,
                                   0x1112131415161718ULL)) ==
              "4f4d504c00010028000200060001000000000002000000000102030405060708"
              "11121314151617180001",
          "exact CANCEL_RESULT golden packet mismatch");
  require(packet_hex(common_packet(Type::protocol_error, outcome)) ==
              "4f4d504c00010028000200070001000000000002000000000102030405060708"
              "00000000000000000001",
          "exact PROTOCOL_ERROR golden packet mismatch");
}

Header selected_header(Role role, Type type, std::uint64_t correlation = 0) {
  return Header{.role = role,
                .type = type,
                .role_version = kRoleVersion,
                .generation = kGeneration,
                .correlation = correlation};
}

void state_machine_test() {
  ReadinessGate readiness;
  for (const Role role : {Role::control, Role::broker, Role::render}) {
    EndpointMachine machine(role);
    WorkerEndpointMachine worker(role);
    const auto welcome_bytes = machine.accept_hello(worker.make_hello(1, 2));
    const auto welcome = decode(welcome_bytes, role);
    require(machine.selected() && welcome.header.type == Type::welcome &&
                welcome.header.role_version == 1 &&
                welcome.header.generation == kGeneration &&
                get32(welcome.payload, 0) == payload_cap(role) &&
                get32(welcome.payload, 4) == kMaxInFlight,
            "independent role HELLO/WELCOME negotiation failed");
    readiness.observe(role, worker.accept_welcome(welcome_bytes));
  }
  require(readiness.ready(),
          "three required endpoints did not reach same-generation readiness");

  ReadinessGate mismatched;
  mismatched.observe(Role::control, kGeneration);
  mismatched.observe(Role::broker, kGeneration);
  mismatched.observe(Role::render, kGeneration + 1);
  require_fatal([&] { (void)mismatched.ready(); },
                "mixed-generation endpoints became ready");

  EndpointMachine broker(Role::broker);
  Header hello{.role = Role::broker, .type = Type::hello};
  broker.accept_hello(encode(hello, hello_payload(1, 1)));

  const auto request = encode(selected_header(Role::broker, Type::request, 41));
  require(
      !broker.accept_selected(request, Direction::worker_to_host).has_value(),
      "valid request was not admitted");
  const auto cancellation = broker.accept_selected(
      encode(selected_header(Role::broker, Type::cancel, 41)),
      Direction::worker_to_host);
  require(cancellation.has_value(), "CANCEL did not produce result");
  const auto cancel_result = decode(*cancellation, Role::broker);
  require(cancel_result.header.type == Type::cancel_result &&
              cancel_result.header.correlation == 41 &&
              get16(cancel_result.payload, 0) == 1,
          "cancellation lost target correlation");
  require(!broker.accept_selected(*cancellation, Direction::host_to_worker)
               .has_value(),
          "CANCEL_RESULT did not correlate to the initiating direction");
  require_fatal(
      [&] { (void)broker.accept_selected(request, Direction::worker_to_host); },
      "correlation was reused before cancelled operation terminated");
  require(!broker
               .accept_selected(
                   encode(selected_header(Role::broker, Type::response, 41)),
                   Direction::host_to_worker)
               .has_value(),
          "cancelled operation did not accept exactly one terminal result");
  require(
      !broker.accept_selected(request, Direction::worker_to_host).has_value(),
      "correlation was not reusable after terminal result");

  const std::array<std::byte, 1> denied_operation{std::byte{0xff}};
  const auto typed_error = broker.accept_selected(
      encode(selected_header(Role::broker, Type::request, 42),
             denied_operation),
      Direction::worker_to_host);
  require(typed_error.has_value(), "recoverable failure had no typed error");
  const auto error = decode(*typed_error, Role::broker);
  require(error.header.type == Type::typed_error &&
              error.header.correlation == 42 && error.payload.size() == 2,
          "typed recoverable error was not correlated and bounded");
  require(!broker
               .accept_selected(
                   encode(selected_header(Role::broker, Type::request, 43)),
                   Direction::worker_to_host)
               .has_value(),
          "endpoint closed after recoverable typed error");

  const auto error_target =
      encode(selected_header(Role::broker, Type::request, 50));
  (void)broker.accept_selected(error_target, Direction::worker_to_host);
  const std::array<std::byte, 2> denied{std::byte{0}, std::byte{1}};
  require(!broker
               .accept_selected(
                   encode(selected_header(Role::broker, Type::typed_error, 50),
                          denied),
                   Direction::host_to_worker)
               .has_value(),
          "received typed error did not terminate matching operation");

  const auto bidirectional =
      encode(selected_header(Role::broker, Type::request, 60));
  (void)broker.accept_selected(bidirectional, Direction::worker_to_host);
  (void)broker.accept_selected(bidirectional, Direction::host_to_worker);

  EndpointMachine crossed(Role::broker);
  crossed.accept_hello(encode(hello, hello_payload(1, 1)));
  const auto crossed_request =
      encode(selected_header(Role::broker, Type::request, 70));
  (void)crossed.accept_selected(crossed_request, Direction::worker_to_host);
  const auto late_cancel_result = crossed.accept_selected(
      encode(selected_header(Role::broker, Type::cancel, 70)),
      Direction::worker_to_host);
  (void)crossed.accept_selected(
      encode(selected_header(Role::broker, Type::response, 70)),
      Direction::host_to_worker);
  require_fatal(
      [&] {
        (void)crossed.accept_selected(crossed_request,
                                      Direction::worker_to_host);
      },
      "correlation reused while crossed CANCEL_RESULT remained outstanding");
  require(late_cancel_result.has_value(),
          "crossed cancellation produced no result");
  (void)crossed.accept_selected(*late_cancel_result, Direction::host_to_worker);
  require(!crossed.accept_selected(crossed_request, Direction::worker_to_host)
               .has_value(),
          "crossed result/cancellation did not retire operation exactly once");
}

void malformed_test() {
  const auto valid = encode(selected_header(Role::control, Type::request, 1));

  auto wrong_role = valid;
  put16(wrong_role, 8, static_cast<std::uint16_t>(Role::broker));
  require_fatal([&] { (void)decode(wrong_role, Role::control); },
                "role substitution was accepted");

  EndpointMachine control(Role::control);
  Header hello{.role = Role::control, .type = Type::hello};
  control.accept_hello(encode(hello, hello_payload(1, 1)));

  auto bad_length = valid;
  put32(bad_length, 16, 1);
  require_fatal([&] { (void)decode(bad_length, Role::control); },
                "length mismatch was accepted");

  auto bad_flags = valid;
  put16(bad_flags, 14, 1);
  require_fatal([&] { (void)decode(bad_flags, Role::control); },
                "nonzero flags were accepted");

  for (const Role role : {Role::control, Role::broker, Role::render}) {
    const auto at_cap = encode(selected_header(role, Type::request, 2),
                               std::vector<std::byte>(payload_cap(role)));
    require(decode(at_cap, role).payload.size() == payload_cap(role),
            "packet at endpoint cap was rejected");
    const auto too_large =
        encode(selected_header(role, Type::request, 3),
               std::vector<std::byte>(payload_cap(role) + 1));
    require_fatal([&] { (void)decode(too_large, role); },
                  "endpoint cap violation was accepted");

    EndpointMachine stale_machine(role);
    Header role_hello{.role = role, .type = Type::hello};
    stale_machine.accept_hello(encode(role_hello, hello_payload(1, 1)));
    auto stale = encode(selected_header(role, Type::request, 8));
    put64(stale, 24, kGeneration - 1);
    require_fatal(
        [&] {
          (void)stale_machine.accept_selected(stale, Direction::worker_to_host);
        },
        "stale generation was accepted");

    EndpointMachine no_overlap(role);
    const auto failed =
        no_overlap.accept_hello(encode(role_hello, hello_payload(2, 3)));
    require(decode(failed, role).header.type == Type::negotiation_failed,
            "no-overlap negotiation did not fail explicitly");
  }

  require_fatal(
      [&] {
        (void)control.accept_selected(
            encode(selected_header(Role::control, Type::request, 0)),
            Direction::worker_to_host);
      },
      "zero request correlation was accepted");

  EndpointMachine correlation_reuse(Role::control);
  correlation_reuse.accept_hello(encode(hello, hello_payload(1, 1)));
  const auto correlated =
      encode(selected_header(Role::control, Type::request, 99));
  (void)correlation_reuse.accept_selected(correlated,
                                          Direction::worker_to_host);
  require_fatal(
      [&] {
        (void)correlation_reuse.accept_selected(correlated,
                                                Direction::worker_to_host);
      },
      "request correlation reuse was accepted");

  EndpointMachine before_welcome(Role::broker);
  require_fatal(
      [&] {
        (void)before_welcome.accept_selected(
            encode(selected_header(Role::broker, Type::request, 1)),
            Direction::worker_to_host);
      },
      "selected message before WELCOME was accepted");

  EndpointMachine duplicate_hello(Role::broker);
  Header broker_hello{.role = Role::broker, .type = Type::hello};
  const auto encoded_hello = encode(broker_hello, hello_payload(1, 1));
  duplicate_hello.accept_hello(encoded_hello);
  require_fatal([&] { (void)duplicate_hello.accept_hello(encoded_hello); },
                "duplicate HELLO was accepted");

  EndpointMachine bounded(Role::broker);
  bounded.accept_hello(encoded_hello);
  for (std::uint64_t correlation = 1; correlation <= kMaxInFlight;
       ++correlation) {
    (void)bounded.accept_selected(
        encode(selected_header(Role::broker, Type::request, correlation)),
        Direction::worker_to_host);
  }
  require_fatal(
      [&] {
        (void)bounded.accept_selected(
            encode(
                selected_header(Role::broker, Type::request, kMaxInFlight + 1)),
            Direction::worker_to_host);
      },
      "maximum in-flight bound was exceeded");

  auto unknown =
      encode(selected_header(Role::control, static_cast<Type>(0x01ff), 71));
  require_fatal(
      [&] {
        (void)control.accept_selected(unknown, Direction::worker_to_host);
      },
      "unknown selected-state message type was accepted");
}

struct Datagram {
  std::vector<std::byte> bytes;
  std::vector<int> quarantined_fds;

  Datagram() = default;
  Datagram(const Datagram &) = delete;
  Datagram &operator=(const Datagram &) = delete;
  Datagram(Datagram &&) = default;
  Datagram &operator=(Datagram &&) = delete;

  ~Datagram() { close_quarantine(); }

  void close_quarantine() noexcept {
    for (const int fd : quarantined_fds) {
      close(fd);
    }
    quarantined_fds.clear();
  }

  int release_one() {
    require(quarantined_fds.size() == 1,
            "descriptor release requires exactly one fd");
    const int fd = quarantined_fds.front();
    quarantined_fds.clear();
    return fd;
  }
};

struct FailureTrace {
  int cleanup_sequence = 0;
  int error_sequence = 0;
  int teardown_sequence = 0;
};

[[noreturn]] void fatal_after_cleanup(Datagram &datagram, FailureTrace *trace,
                                      std::string_view message) {
  datagram.close_quarantine();
  if (trace != nullptr) {
    trace->cleanup_sequence = 1;
    trace->error_sequence = 2;
    trace->teardown_sequence = 3;
  }
  throw FatalError(std::string(message));
}

class OwnedFd {
public:
  explicit OwnedFd(int fd = -1) : fd_(fd) {}
  OwnedFd(const OwnedFd &) = delete;
  OwnedFd &operator=(const OwnedFd &) = delete;
  OwnedFd(OwnedFd &&other) noexcept : fd_(other.fd_) { other.fd_ = -1; }
  OwnedFd &operator=(OwnedFd &&other) noexcept {
    if (this != &other) {
      if (fd_ >= 0) {
        close(fd_);
      }
      fd_ = other.fd_;
      other.fd_ = -1;
    }
    return *this;
  }
  ~OwnedFd() {
    if (fd_ >= 0) {
      close(fd_);
    }
  }
  [[nodiscard]] int get() const { return fd_; }

private:
  int fd_;
};

void identity_model_test() {
  const int pidfd = static_cast<int>(syscall(SYS_pidfd_open, getpid(), 0));
  require(pidfd >= 0, "pidfd_open failed for identity fixture");
  OwnedFd pidfd_owner(pidfd);
  const PeerCredentials self{
      .pid = getpid(), .uid = geteuid(), .gid = getegid()};
  const LaunchBinding binding{.worker = self, .pidfd = pidfd};
  bool pidfd_hook_called = false;
  validate_daemon_peer(self, binding, [&](int candidate) {
    pidfd_hook_called = true;
    return candidate == pidfd && fcntl(candidate, F_GETFD) >= 0;
  });
  require(pidfd_hook_called, "daemon validation bypassed pidfd hook");
  auto wrong_pid = self;
  ++wrong_pid.pid;
  require_fatal(
      [&] {
        validate_daemon_peer(wrong_pid, binding, [](int) { return true; });
      },
      "daemon accepted credentials outside launch binding");
  require_fatal(
      [&] { validate_daemon_peer(self, binding, [](int) { return false; }); },
      "daemon accepted failed pidfd association");

  int sockets[2];
  require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) == 0,
          "identity socketpair failed");
  OwnedFd first(sockets[0]);
  OwnedFd second(sockets[1]);
  ucred peer{};
  socklen_t peer_size = sizeof(peer);
  require(getsockopt(first.get(), SOL_SOCKET, SO_PEERCRED, &peer, &peer_size) ==
                  0 &&
              peer_size == sizeof(peer),
          "SO_PEERCRED baseline failed");
  const PeerCredentials baseline{
      .pid = peer.pid, .uid = peer.uid, .gid = peer.gid};
  validate_worker_peer(baseline, baseline);

  const PeerCredentials translated_zero{
      .pid = 0, .uid = geteuid(), .gid = getegid()};
  validate_worker_peer(translated_zero, translated_zero);
  auto inconsistent_zero = translated_zero;
  inconsistent_zero.pid = 1;
  require_fatal(
      [&] { validate_worker_peer(translated_zero, inconsistent_zero); },
      "worker accepted nonzero packet PID against translated-zero baseline");
  auto inconsistent_user = translated_zero;
  ++inconsistent_user.uid;
  require_fatal(
      [&] { validate_worker_peer(translated_zero, inconsistent_user); },
      "worker accepted credentials with inconsistent translated UID");
}

void send_with_fds(int fd, std::span<const std::byte> bytes,
                   std::span<const int> descriptors) {
  require(!descriptors.empty() && descriptors.size() <= 8,
          "descriptor sender fixture accepts one to eight fds");
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(int) * 8)> control{};
  iovec iov{.iov_base = const_cast<std::byte *>(bytes.data()),
            .iov_len = bytes.size()};
  msghdr message{};
  message.msg_iov = &iov;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = CMSG_SPACE(sizeof(int) * descriptors.size());
  auto *item = CMSG_FIRSTHDR(&message);
  item->cmsg_level = SOL_SOCKET;
  item->cmsg_type = SCM_RIGHTS;
  item->cmsg_len = CMSG_LEN(sizeof(int) * descriptors.size());
  std::memcpy(CMSG_DATA(item), descriptors.data(),
              sizeof(int) * descriptors.size());
  require(sendmsg(fd, &message, MSG_NOSIGNAL) ==
              static_cast<ssize_t>(bytes.size()),
          "descriptor send failed");
}

Datagram receive_datagram(int fd, Role role, FailureTrace *trace = nullptr) {
  std::vector<std::byte> bytes(kHeaderSize + payload_cap(role));
  alignas(cmsghdr) std::array<std::byte, CMSG_SPACE(sizeof(ucred)) +
                                             CMSG_SPACE(sizeof(int) * 4)>
      control{};
  iovec iov{.iov_base = bytes.data(), .iov_len = bytes.size()};
  msghdr message{};
  message.msg_iov = &iov;
  message.msg_iovlen = 1;
  message.msg_control = control.data();
  message.msg_controllen = control.size();
  const auto received = recvmsg(fd, &message, MSG_TRUNC | MSG_CMSG_CLOEXEC);
  require(received >= 0, "descriptor recv failed");

  Datagram datagram;
  datagram.quarantined_fds.reserve(4);
  std::optional<ucred> credentials;
  bool invalid_ancillary = false;
  for (auto *item = CMSG_FIRSTHDR(&message); item != nullptr;
       item = CMSG_NXTHDR(&message, item)) {
    if (item->cmsg_level == SOL_SOCKET && item->cmsg_type == SCM_RIGHTS &&
        item->cmsg_len >= CMSG_LEN(0)) {
      const auto payload_bytes = item->cmsg_len - CMSG_LEN(0);
      const auto count = payload_bytes / sizeof(int);
      const auto *received_fds = reinterpret_cast<const int *>(CMSG_DATA(item));
      for (std::size_t index = 0; index < count; ++index) {
        datagram.quarantined_fds.push_back(received_fds[index]);
      }
      if (payload_bytes % sizeof(int) != 0 ||
          datagram.quarantined_fds.size() > 4) {
        invalid_ancillary = true;
      }
    } else if (item->cmsg_level == SOL_SOCKET &&
               item->cmsg_type == SCM_CREDENTIALS &&
               item->cmsg_len == CMSG_LEN(sizeof(ucred))) {
      if (credentials.has_value()) {
        invalid_ancillary = true;
      } else {
        ucred value;
        std::memcpy(&value, CMSG_DATA(item), sizeof(value));
        credentials = value;
      }
    } else {
      invalid_ancillary = true;
    }
  }
  if ((message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) != 0 ||
      invalid_ancillary) {
    fatal_after_cleanup(datagram, trace,
                        "truncated or malformed ancillary data");
  }
  if (!credentials.has_value() || credentials->pid != getpid() ||
      credentials->uid != geteuid() || credentials->gid != getegid()) {
    fatal_after_cleanup(datagram, trace, "missing or wrong kernel credentials");
  }
  bytes.resize(static_cast<std::size_t>(received));
  datagram.bytes = std::move(bytes);
  return datagram;
}

std::optional<OwnedFd>
enforce_descriptor_policy(Datagram &datagram, Role role, Direction direction,
                          FailureTrace *trace = nullptr) {
  Packet packet;
  try {
    packet = decode(datagram.bytes, role);
  } catch (...) {
    fatal_after_cleanup(datagram, trace, "invalid descriptor envelope");
  }

  if (datagram.quarantined_fds.empty()) {
    if (role == Role::render && direction == Direction::host_to_worker &&
        packet.header.type == Type::render_buffer) {
      fatal_after_cleanup(datagram, trace,
                          "descriptor-bearing message omitted descriptor");
    }
    return std::nullopt;
  }
  if (role != Role::render || direction != Direction::host_to_worker ||
      packet.header.type != Type::render_buffer ||
      packet.header.role_version != kRoleVersion ||
      packet.header.generation != kGeneration ||
      packet.header.correlation != 0 || packet.payload.size() != 8 ||
      get32(packet.payload, 0) != 0x52423031 ||
      get32(packet.payload, 4) != 4096 ||
      datagram.quarantined_fds.size() != 1) {
    fatal_after_cleanup(datagram, trace,
                        "descriptor policy or schema violation");
  }

  const int candidate = datagram.quarantined_fds.front();
  struct stat status{};
  const int descriptor_flags = fcntl(candidate, F_GETFD);
  const int access_flags = fcntl(candidate, F_GETFL);
  const int seals = fcntl(candidate, F_GET_SEALS);
  constexpr int required_seals =
      F_SEAL_SEAL | F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE;
  if (fstat(candidate, &status) != 0 || !S_ISREG(status.st_mode) ||
      status.st_size != 4096 || descriptor_flags < 0 ||
      (descriptor_flags & FD_CLOEXEC) == 0 || access_flags < 0 ||
      (access_flags & O_ACCMODE) != O_RDONLY || seals < 0 ||
      (seals & required_seals) != required_seals) {
    fatal_after_cleanup(datagram, trace, "render descriptor validation failed");
  }

  return OwnedFd(datagram.release_one());
}

std::set<int> open_fd_set() {
  std::set<int> descriptors;
  for (int fd = 0; fd < 1024; ++fd) {
    errno = 0;
    if (fcntl(fd, F_GETFD) >= 0 || errno != EBADF) {
      descriptors.insert(fd);
    }
  }
  return descriptors;
}

std::array<std::byte, 8> render_buffer_payload() {
  std::array<std::byte, 8> payload{};
  put32(payload, 0, 0x52423031);
  put32(payload, 4, 4096);
  return payload;
}

OwnedFd make_readonly_render_fixture() {
  const int writable =
      memfd_create("plugin-envelope-render", MFD_CLOEXEC | MFD_ALLOW_SEALING);
  require(writable >= 0, "cannot create render memfd fixture");
  OwnedFd writable_owner(writable);
  constexpr int seals =
      F_SEAL_SEAL | F_SEAL_SHRINK | F_SEAL_GROW | F_SEAL_WRITE;
  require(ftruncate(writable, 4096) == 0 &&
              fcntl(writable, F_ADD_SEALS, seals) == 0,
          "cannot size and seal render memfd fixture");
  const std::string path = "/proc/self/fd/" + std::to_string(writable);
  const int readonly = open(path.c_str(), O_RDONLY | O_CLOEXEC);
  require(readonly >= 0, "cannot reopen render memfd read-only");
  return OwnedFd(readonly);
}

void descriptor_policy_test() {
  constexpr int repeats = 32;
  for (const Role role : {Role::control, Role::broker, Role::render}) {
    int sockets[2];
    require(socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, sockets) == 0,
            "descriptor socketpair failed");
    int enabled = 1;
    require(setsockopt(sockets[0], SOL_SOCKET, SO_PASSCRED, &enabled,
                       sizeof(enabled)) == 0,
            "SO_PASSCRED failed");
    OwnedFd source = make_readonly_render_fixture();
    const std::array<int, 1> descriptor{source.get()};
    const auto ordinary = encode(selected_header(role, Type::request, 10));
    const auto render_buffer = encode(
        selected_header(role, Type::render_buffer), render_buffer_payload());
    const auto before = open_fd_set();

    for (int iteration = 0; iteration < repeats; ++iteration) {
      const bool accepted_render = role == Role::render;
      send_with_fds(sockets[1], accepted_render ? render_buffer : ordinary,
                    descriptor);
      auto datagram = receive_datagram(sockets[0], role);
      if (accepted_render) {
        const auto transferred = enforce_descriptor_policy(
            datagram, role, Direction::host_to_worker);
        require(transferred.has_value() && transferred->get() >= 0,
                "validated render descriptor was not transferred");
      } else {
        require_fatal(
            [&] {
              (void)enforce_descriptor_policy(datagram, role,
                                              Direction::worker_to_host);
            },
            "control or broker descriptor was accepted");
      }
      require(open_fd_set() == before,
              "descriptor path changed fd count during repetition");
    }

    if (role == Role::render) {
      send_with_fds(sockets[1], render_buffer, descriptor);
      auto datagram = receive_datagram(sockets[0], role);
      require_fatal(
          [&] {
            (void)enforce_descriptor_policy(datagram, role,
                                            Direction::worker_to_host);
          },
          "worker-to-host render descriptor was accepted");
      require(open_fd_set() == before,
              "malformed render direction leaked a received fd");

      const std::array<int, 2> excess{source.get(), source.get()};
      send_with_fds(sockets[1], render_buffer, excess);
      auto excess_datagram = receive_datagram(sockets[0], role);
      require_fatal(
          [&] {
            (void)enforce_descriptor_policy(excess_datagram, role,
                                            Direction::host_to_worker);
          },
          "excess render descriptors were accepted");
      require(open_fd_set() == before,
              "excess render descriptors leaked received fds");

      const std::array<int, 5> truncated{
          source.get(), source.get(), source.get(), source.get(), source.get()};
      send_with_fds(sockets[1], render_buffer, truncated);
      FailureTrace truncation_trace;
      require_fatal(
          [&] { (void)receive_datagram(sockets[0], role, &truncation_trace); },
          "ancillary truncation was accepted");
      require(truncation_trace.cleanup_sequence == 1 &&
                  truncation_trace.error_sequence == 2 &&
                  truncation_trace.teardown_sequence == 3,
              "truncation cleanup did not precede error and teardown");
      require(open_fd_set() == before,
              "ancillary truncation leaked delivered descriptors");

      send_with_fds(sockets[1], ordinary, descriptor);
      auto wrong_schema = receive_datagram(sockets[0], role);
      require_fatal(
          [&] {
            (void)enforce_descriptor_policy(wrong_schema, role,
                                            Direction::host_to_worker);
          },
          "descriptor on untyped render message was accepted");
      require(open_fd_set() == before,
              "schema-rejected render descriptor leaked a received fd");

      auto malformed_envelope = render_buffer;
      put16(malformed_envelope, 14, 1);
      send_with_fds(sockets[1], malformed_envelope, descriptor);
      auto malformed_datagram = receive_datagram(sockets[0], role);
      FailureTrace malformed_trace;
      require_fatal(
          [&] {
            (void)enforce_descriptor_policy(malformed_datagram, role,
                                            Direction::host_to_worker,
                                            &malformed_trace);
          },
          "descriptor on malformed envelope was accepted");
      require(malformed_trace.cleanup_sequence == 1 &&
                  malformed_trace.error_sequence == 2 &&
                  malformed_trace.teardown_sequence == 3,
              "policy cleanup did not precede error and teardown");
      require(open_fd_set() == before,
              "malformed-envelope descriptor leaked a received fd");

      require(send(sockets[1], render_buffer.data(), render_buffer.size(),
                   MSG_NOSIGNAL) == static_cast<ssize_t>(render_buffer.size()),
              "zero-descriptor render send failed");
      auto missing_descriptor = receive_datagram(sockets[0], role);
      require_fatal(
          [&] {
            (void)enforce_descriptor_policy(missing_descriptor, role,
                                            Direction::host_to_worker);
          },
          "descriptor-bearing render message accepted zero descriptors");
      require(open_fd_set() == before,
              "zero-descriptor rejection changed open fd set");
    }

    require(open_fd_set() == before, "descriptor test leaked a received fd");
    close(sockets[0]);
    close(sockets[1]);
  }
}

} // namespace

int main() {
  try {
    golden_header_test();
    state_machine_test();
    malformed_test();
    identity_model_test();
    descriptor_policy_test();
    std::cout << "golden_header=40 negotiation=three-role-v1 "
                 "generation=validated cancellation=correlated "
                 "typed_error=recoverable fatal_cases=denied "
                 "descriptor_policy=denied-or-typed identity=bound\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "plugin-envelope-spike: " << error.what() << '\n';
    return 1;
  }
}
