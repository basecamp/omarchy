#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <fcntl.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace {

constexpr std::uint32_t kMagic = 0x4f505256;
constexpr std::size_t kHeader = 20;

[[noreturn]] void fail(std::string_view message) {
  std::cerr << "FAIL: " << message << '\n';
  std::exit(1);
}

void require(bool condition, std::string_view message) {
  if (!condition)
    fail(message);
}

void put_u16(std::vector<std::byte> &bytes, std::uint16_t value) {
  bytes.push_back(static_cast<std::byte>(value >> 8));
  bytes.push_back(static_cast<std::byte>(value));
}

void put_u32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void put_u64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

std::uint32_t u32(std::span<const std::byte> bytes, std::size_t offset) {
  require(offset + 4 <= bytes.size(), "truncated u32");
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index)
    value = (value << 8U) |
            std::to_integer<unsigned char>(bytes[offset + index]);
  return value;
}

void put_text(std::vector<std::byte> &bytes, std::string_view value) {
  put_u16(bytes, static_cast<std::uint16_t>(value.size()));
  const auto raw = std::as_bytes(std::span(value.data(), value.size()));
  bytes.insert(bytes.end(), raw.begin(), raw.end());
}

std::vector<std::byte> request(std::uint64_t correlation,
                               std::string_view profile,
                               std::string_view command,
                               std::span<const std::string_view> arguments) {
  QJsonArray json_arguments;
  for (const auto argument : arguments)
    json_arguments.append(QString::fromUtf8(argument));
  const auto payload =
      QJsonDocument(QJsonObject{{"command", QString::fromUtf8(command)},
                                {"arguments", json_arguments}})
          .toJson(QJsonDocument::Compact);
  std::vector<std::byte> body;
  put_text(body, "bounded-command-execute");
  put_text(body,
           "7cfb8547d49ea0d43248227c049f19d9f711c7838452789c9ef2fdfe41e82142");
  put_u32(body, 1);
  put_text(body, "run");
  put_text(body, "{\"profile\":\"" + std::string(profile) + "\"}");
  put_u32(body, static_cast<std::uint32_t>(payload.size()));
  const auto payload_bytes = std::as_bytes(
      std::span(payload.constData(), static_cast<std::size_t>(payload.size())));
  body.insert(body.end(), payload_bytes.begin(), payload_bytes.end());

  std::vector<std::byte> frame;
  put_u32(frame, kMagic);
  frame.push_back(std::byte{1});
  frame.push_back(std::byte{1});
  frame.push_back(std::byte{0});
  frame.push_back(std::byte{0});
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(body.size()));
  frame.insert(frame.end(), body.begin(), body.end());
  return frame;
}

QJsonObject roundtrip(int channel, const std::vector<std::byte> &frame) {
  iovec request_part{.iov_base = const_cast<std::byte *>(frame.data()),
                     .iov_len = frame.size()};
  msghdr request_message{};
  request_message.msg_iov = &request_part;
  request_message.msg_iovlen = 1;
  const auto sent = ::sendmsg(channel, &request_message, MSG_NOSIGNAL);
  if (sent != static_cast<ssize_t>(frame.size())) {
    std::cerr << "send result=" << sent << " errno=" << errno << '\n';
    fail("request send failed");
  }
  std::array<std::byte, 70 * 1024> response{};
  iovec response_part{.iov_base = response.data(),
                      .iov_len = response.size()};
  msghdr response_message{};
  response_message.msg_iov = &response_part;
  response_message.msg_iovlen = 1;
  const auto received = ::recvmsg(channel, &response_message, 0);
  require(received > static_cast<ssize_t>(kHeader), "response receive failed");
  const auto bytes = std::span(response.data(),
                               static_cast<std::size_t>(received));
  require(u32(bytes, 0) == kMagic && bytes[4] == std::byte{1} &&
              bytes[5] == std::byte{2} && bytes[kHeader] == std::byte{0} &&
              u32(bytes, 16) + kHeader == bytes.size(),
          "response framing invalid");
  const auto document = QJsonDocument::fromJson(QByteArray(
      reinterpret_cast<const char *>(bytes.data() + kHeader + 1),
      static_cast<qsizetype>(bytes.size() - kHeader - 1)));
  require(document.isObject(), "response JSON invalid");
  return document.object();
}

struct Child final {
  pid_t pid = -1;
  int channel = -1;
};

Child start(std::string_view policy_root, bool validate_only = false) {
  int pair[2] = {-1, -1};
  require(::socketpair(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0, pair) == 0,
          "socketpair failed");
  const pid_t pid = ::fork();
  require(pid >= 0, "fork failed");
  if (pid == 0) {
    ::close(pair[0]);
    if (pair[1] != 3 && ::dup2(pair[1], 3) != 3)
      _exit(126);
    if (pair[1] != 3)
      ::close(pair[1]);
    (void)::fcntl(3, F_SETFD, 0);
    const auto uid = std::to_string(::getuid());
    if (validate_only) {
      ::execl(COMMAND_EXECUTOR_PATH, COMMAND_EXECUTOR_PATH,
              std::string(policy_root).c_str(), MISSING_POLICY_ROOT,
              uid.c_str(), "--validate-only", static_cast<char *>(nullptr));
    } else {
      ::execl(COMMAND_EXECUTOR_PATH, COMMAND_EXECUTOR_PATH,
              std::string(policy_root).c_str(), MISSING_POLICY_ROOT,
              uid.c_str(), static_cast<char *>(nullptr));
    }
    _exit(127);
  }
  ::close(pair[1]);
  return {.pid = pid, .channel = pair[0]};
}

int finish(Child child) {
  ::close(child.channel);
  int status = 0;
  while (::waitpid(child.pid, &status, 0) < 0 && errno == EINTR) {}
  return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

} // namespace

int main() {
  auto child = start(POLICY_ROOT);
  const std::array<std::string_view, 2> print_arguments{"%s", "hello"};
  auto response = roundtrip(
      child.channel,
      request(1, "test-printf", "printf", print_arguments));
  require(response.value("exitCode").toInt(-1) == 0 &&
              response.value("stdout").toString() == "hello" &&
              response.value("stderr").toString().isEmpty(),
          "accepted exact argv did not execute the pinned program");

  const std::array<std::string_view, 2> rejected_arguments{"%s", "@secret"};
  response = roundtrip(child.channel,
                      request(2, "test-printf", "printf",
                              rejected_arguments));
  require(response.value("exitCode").toInt() == 126 &&
              response.value("stderr").toString() == "command-rejected",
          "argument outside the trusted grammar executed");

  response = roundtrip(child.channel,
                      request(3, "test-output-limit", "yes", {}));
  require(response.value("exitCode").toInt() == 125 &&
              response.value("stderr").toString() == "command-output-limit",
          "unbounded output escaped the policy ceiling");

  const std::array<std::string_view, 1> sleep_arguments{"5"};
  response = roundtrip(child.channel,
                      request(4, "test-timeout", "sleep", sleep_arguments));
  require(response.value("exitCode").toInt() == 124 &&
              response.value("timedOut").toBool() &&
              response.value("stderr").toString() == "command-timeout",
          "long-running command escaped the policy deadline");
  require(finish(child) == 0, "executor did not exit cleanly");

  child = start(REJECTED_POLICY_ROOT);
  require(finish(child) == 78, "shell policy was accepted");

  child = start(BUILTIN_POLICY_ROOT, true);
  const std::array<std::string_view, 4> mark_arguments{
      "api", "--method", "PATCH", "/notifications/threads/12345"};
  response = roundtrip(child.channel,
                       request(5, "github-api-v1", "gh", mark_arguments));
  require(response.value("exitCode").toInt(-1) == 0 &&
              response.value("stdout").toString() == "policy-accepted",
          "reviewed GitHub notification argv was rejected");

  const std::array<std::string_view, 4> auth_arguments{
      "auth", "status", "--hostname", "github.com"};
  const std::array<std::string_view, 4> notification_arguments{
      "api", "-H",
      "Accept: application/vnd.github+json",
      "/notifications?all=false&participating=false&per_page=10&page=1"};
  const std::array<std::string_view, 4> search_arguments{
      "api", "-H",
      "Accept: application/vnd.github+json",
      "/search/issues?q=is%3Aopen+is%3Apr+review-requested%3A%40me+draft%3Afalse+archived%3Afalse&per_page=10&page=37"};
  const std::array<std::string_view, 6> pull_arguments{
      "api", "graphql", "-f",
      "query=query($search:String!) { search(query:$search,type:ISSUE,first:50) { issueCount nodes { ... on PullRequest { number title url updatedAt isDraft repository { nameWithOwner } commits(last:1) { nodes { commit { statusCheckRollup { state } } } } } } } } }",
      "-F", "search=is:open is:pr author:@me sort:updated-desc archived:false"};
  const std::array<std::string_view, 4> repository_arguments{
      "api", "graphql", "-f",
      "query=query($cursor:String) { viewer { login repositories(first:100,after:$cursor,ownerAffiliations:[OWNER,ORGANIZATION_MEMBER],orderBy:{field:UPDATED_AT,direction:DESC}) { nodes { name nameWithOwner url isArchived isFork stargazerCount updatedAt issues(states:OPEN){totalCount} pullRequests(states:OPEN){totalCount} } pageInfo { hasNextPage endCursor } } } rateLimit { remaining resetAt cost } }"};
  for (const auto &[correlation, arguments] :
       std::array<std::pair<std::uint64_t, std::span<const std::string_view>>, 5>{
           std::pair{std::uint64_t{11}, std::span<const std::string_view>(auth_arguments)},
           std::pair{std::uint64_t{12}, std::span<const std::string_view>(notification_arguments)},
           std::pair{std::uint64_t{13}, std::span<const std::string_view>(search_arguments)},
           std::pair{std::uint64_t{14}, std::span<const std::string_view>(pull_arguments)},
           std::pair{std::uint64_t{15}, std::span<const std::string_view>(repository_arguments)}}) {
    response = roundtrip(
        child.channel, request(correlation, "github-api-v1", "gh", arguments));
    require(response.value("exitCode").toInt(-1) == 0,
            "reviewed GitHub read argv was rejected");
  }

  const auto rejected = [&](std::uint64_t correlation,
                            std::span<const std::string_view> arguments) {
    const auto result = roundtrip(
        child.channel,
        request(correlation, "github-api-v1", "gh", arguments));
    return result.value("exitCode").toInt() == 126 &&
           result.value("stderr").toString() == "command-rejected";
  };
  const std::array<std::string_view, 3> token_arguments{
      "auth", "status", "--show-token"};
  const std::array<std::string_view, 3> input_arguments{
      "api", "--input", "/etc/passwd"};
  const std::array<std::string_view, 2> content_arguments{
      "api", "/repos/private/project/contents/secret"};
  const std::array<std::string_view, 6> file_field_arguments{
      "api", "--method", "PUT", "/notifications", "-f",
      "last_read_at=@/etc/passwd"};
  const std::array<std::string_view, 4> alternate_host_arguments{
      "auth", "status", "--hostname", "attacker.example"};
  const std::array<std::string_view, 4> unbounded_page_arguments{
      "api", "-H", "Accept: application/vnd.github+json",
      "/notifications?all=false&participating=false&per_page=100&page=1"};
  const std::array<std::string_view, 4> zero_page_arguments{
      "api", "-H", "Accept: application/vnd.github+json",
      "/notifications?all=false&participating=false&per_page=10&page=0"};
  require(rejected(16, token_arguments) && rejected(17, input_arguments) &&
              rejected(18, content_arguments) &&
              rejected(19, file_field_arguments) &&
              rejected(20, alternate_host_arguments) &&
              rejected(21, unbounded_page_arguments) &&
              rejected(22, zero_page_arguments),
          "GitHub profile admitted a token, file, broad endpoint, alternate host, or unbounded page escape");
  require(finish(child) == 0, "GitHub policy validator did not exit cleanly");
  std::cout << "command executor tests passed\n";
}
