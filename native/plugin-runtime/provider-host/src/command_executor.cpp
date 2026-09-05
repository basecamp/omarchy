#include "command_contract.hpp"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <charconv>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <span>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

constexpr std::uint32_t kProtocolMagic = 0x4f505256;
constexpr std::uint8_t kProtocolVersion = 1;
constexpr std::uint8_t kRequestType = 1;
constexpr std::uint8_t kResponseType = 2;
constexpr std::size_t kHeaderBytes = 20;
constexpr std::size_t kMaximumFrameBytes = 64 * 1024 + kHeaderBytes;
constexpr std::size_t kMaximumPolicyBytes = 128 * 1024;
constexpr std::size_t kMaximumPolicies = 64;
constexpr std::size_t kMaximumRules = 128;
constexpr std::size_t kMaximumMatchers = 64;
constexpr std::size_t kMaximumArgumentBytes = 4096;
constexpr std::size_t kMaximumTotalArgumentBytes = 16 * 1024;
constexpr std::size_t kMaximumStdoutBytes = 48 * 1024;
constexpr std::size_t kMaximumStderrBytes = 8 * 1024;
constexpr std::chrono::milliseconds kMaximumCommandTimeout{29000};

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
  void reset(int value = -1) noexcept {
    if (value_ >= 0)
      ::close(value_);
    value_ = value;
  }

private:
  int value_ = -1;
};

struct Matcher final {
  std::optional<std::string> exact;
  QRegularExpression expression;
};

struct Rule final {
  std::vector<Matcher> arguments;
};

struct Policy final {
  std::string profile;
  std::string command;
  std::string executable_path;
  std::uint32_t trusted_uid = 0;
  std::chrono::milliseconds timeout{};
  std::size_t stdout_limit = 0;
  std::size_t stderr_limit = 0;
  bool account_home = false;
  std::vector<std::pair<QByteArray, QByteArray>> environment;
  std::vector<Rule> rules;
};

bool trusted_owner(uid_t owner, uid_t trusted_uid) {
#ifdef OMARCHY_COMMAND_EXECUTOR_TESTING
  (void)owner;
  (void)trusted_uid;
  return true;
#else
  return owner == 0 || owner == trusted_uid;
#endif
}

std::uint16_t u16(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 2 > bytes.size()) {
    ok = false;
    return 0;
  }
  return static_cast<std::uint16_t>(
      (std::to_integer<unsigned char>(bytes[offset]) << 8U) |
      std::to_integer<unsigned char>(bytes[offset + 1]));
}

std::uint32_t u32(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 4 > bytes.size()) {
    ok = false;
    return 0;
  }
  std::uint32_t value = 0;
  for (std::size_t index = 0; index < 4; ++index)
    value = (value << 8U) |
            std::to_integer<unsigned char>(bytes[offset + index]);
  return value;
}

std::uint64_t u64(std::span<const std::byte> bytes, std::size_t offset,
                  bool &ok) {
  if (offset + 8 > bytes.size()) {
    ok = false;
    return 0;
  }
  std::uint64_t value = 0;
  for (std::size_t index = 0; index < 8; ++index)
    value = (value << 8U) |
            std::to_integer<unsigned char>(bytes[offset + index]);
  return value;
}

void put_u32(std::vector<std::byte> &bytes, std::uint32_t value) {
  for (int shift = 24; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

void put_u64(std::vector<std::byte> &bytes, std::uint64_t value) {
  for (int shift = 56; shift >= 0; shift -= 8)
    bytes.push_back(static_cast<std::byte>(value >> shift));
}

bool read_text(std::span<const std::byte> bytes, std::size_t &offset,
               std::string_view &value) {
  bool ok = true;
  const auto size = u16(bytes, offset, ok);
  offset += 2;
  if (!ok || offset + size > bytes.size())
    return false;
  value = std::string_view(
      reinterpret_cast<const char *>(bytes.data() + offset), size);
  offset += size;
  return value.find('\0') == std::string_view::npos;
}

bool canonical_component(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  return std::ranges::all_of(value, [](unsigned char byte) {
    return (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') ||
           byte == '-' || byte == '_' || byte == '.';
  });
}

bool secure_directory(const struct stat &metadata, uid_t uid) {
  return S_ISDIR(metadata.st_mode) && trusted_owner(metadata.st_uid, uid) &&
         (metadata.st_mode & 0022) == 0;
}

bool canonical_absolute_path(std::string_view path) {
  if (path.size() < 2 || path.size() > 4096 || path.front() != '/' ||
      path.back() == '/' || path.find('\0') != std::string_view::npos)
    return false;
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    if (component.empty() || component == "." || component == "..")
      return false;
    begin = end == std::string_view::npos ? path.size() : end + 1;
  }
  return true;
}

Descriptor open_secure(std::string_view path, uid_t uid, bool executable) {
  if (!canonical_absolute_path(path))
    return {};
  Descriptor current(::open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC |
                                     O_NOFOLLOW));
  struct stat metadata {};
  if (!current || ::fstat(current.get(), &metadata) < 0 ||
      !secure_directory(metadata, uid))
    return {};
  std::size_t begin = 1;
  while (begin < path.size()) {
    const auto end = path.find('/', begin);
    const auto component = path.substr(
        begin, end == std::string_view::npos ? path.size() - begin : end - begin);
    const bool leaf = end == std::string_view::npos;
    const std::string name(component);
    Descriptor next(::openat(
        current.get(), name.c_str(),
        (leaf ? O_RDONLY | O_NONBLOCK : O_RDONLY | O_DIRECTORY) | O_CLOEXEC |
            O_NOFOLLOW));
    if (!next || ::fstat(next.get(), &metadata) < 0)
      return {};
    if (leaf) {
      const bool mode_ok = executable ? (metadata.st_mode & 0100) != 0 : true;
      if (!S_ISREG(metadata.st_mode) ||
          !trusted_owner(metadata.st_uid, uid) ||
          (metadata.st_mode & 0022) != 0 ||
          (metadata.st_mode & (S_ISUID | S_ISGID)) != 0 || !mode_ok ||
          metadata.st_size < 0)
        return {};
      return next;
    }
    if (!secure_directory(metadata, uid))
      return {};
    current = std::move(next);
    begin = end + 1;
  }
  return {};
}

std::optional<QByteArray> read_bounded(int fd, std::size_t limit) {
  QByteArray result;
  std::array<char, 8192> buffer{};
  while (true) {
    const auto count = ::read(fd, buffer.data(), buffer.size());
    if (count < 0) {
      if (errno == EINTR)
        continue;
      return std::nullopt;
    }
    if (count == 0)
      return result;
    if (result.size() > static_cast<qsizetype>(limit -
                                               static_cast<std::size_t>(count)))
      return std::nullopt;
    result.append(buffer.data(), count);
  }
}

std::optional<std::uint32_t> positive_u32(const QJsonValue &value,
                                          std::uint32_t maximum) {
  if (!value.isDouble())
    return std::nullopt;
  const double number = value.toDouble();
  if (number < 1 || number > maximum || number != std::floor(number))
    return std::nullopt;
  return static_cast<std::uint32_t>(number);
}

bool exact_keys(const QJsonObject &object,
                std::span<const std::string_view> allowed) {
  return std::ranges::all_of(object.keys(), [&](const QString &key) {
    const auto utf8 = key.toUtf8().toStdString();
    return std::ranges::find(allowed, utf8) != allowed.end();
  });
}

std::optional<Policy> parse_policy(const QByteArray &document,
                                   uid_t trusted_uid) {
  QJsonParseError error{};
  const auto parsed = QJsonDocument::fromJson(document, &error);
  if (error.error != QJsonParseError::NoError || !parsed.isObject())
    return std::nullopt;
  const auto object = parsed.object();
  constexpr std::array keys{
      std::string_view("schemaVersion"), std::string_view("profile"),
      std::string_view("command"), std::string_view("executable"),
      std::string_view("timeoutMs"), std::string_view("stdoutBytes"),
      std::string_view("stderrBytes"), std::string_view("accountHome"),
      std::string_view("environment"), std::string_view("rules")};
  if (!exact_keys(object, keys) || object.value("schemaVersion").toInt() != 1 ||
      !object.value("profile").isString() ||
      !object.value("command").isString() ||
      !object.value("executable").isString() ||
      !object.value("accountHome").isBool() ||
      !object.value("environment").isObject() ||
      !object.value("rules").isArray())
    return std::nullopt;
  Policy policy;
  policy.profile = object.value("profile").toString().toStdString();
  policy.command = object.value("command").toString().toStdString();
  policy.executable_path = object.value("executable").toString().toStdString();
  const auto timeout = positive_u32(object.value("timeoutMs"),
                                    kMaximumCommandTimeout.count());
  const auto stdout_limit = positive_u32(object.value("stdoutBytes"),
                                         kMaximumStdoutBytes);
  const auto stderr_limit = positive_u32(object.value("stderrBytes"),
                                         kMaximumStderrBytes);
  static constexpr std::array forbidden_commands{
      std::string_view("bash"), std::string_view("dash"),
      std::string_view("fish"), std::string_view("sh"),
      std::string_view("zsh")};
  if (!canonical_component(policy.profile) ||
      !canonical_component(policy.command) ||
      std::ranges::find(forbidden_commands, policy.command) !=
          forbidden_commands.end() ||
      !canonical_absolute_path(policy.executable_path) || !timeout ||
      !stdout_limit || !stderr_limit)
    return std::nullopt;
  policy.trusted_uid = trusted_uid;
  policy.timeout = std::chrono::milliseconds(*timeout);
  policy.stdout_limit = *stdout_limit;
  policy.stderr_limit = *stderr_limit;
  policy.account_home = object.value("accountHome").toBool();
  const auto environment = object.value("environment").toObject();
  if (environment.size() > 16)
    return std::nullopt;
  static const QRegularExpression environment_name(
      QStringLiteral("\\A[A-Z][A-Z0-9_]{0,63}\\z"));
  for (auto iterator = environment.begin(); iterator != environment.end();
       ++iterator) {
    if (!iterator.value().isString() ||
        !environment_name.match(iterator.key()).hasMatch() ||
        iterator.key() == QStringLiteral("PATH") ||
        iterator.key() == QStringLiteral("HOME") ||
        iterator.key() == QStringLiteral("LANG") ||
        iterator.key() == QStringLiteral("LC_ALL") ||
        iterator.key().startsWith(QStringLiteral("LD_")) ||
        iterator.key().startsWith(QStringLiteral("QT_")))
      return std::nullopt;
    const auto value = iterator.value().toString().toUtf8();
    if (value.size() > 1024 || value.contains('\0'))
      return std::nullopt;
    policy.environment.emplace_back(iterator.key().toUtf8(), value);
  }

  const auto rules = object.value("rules").toArray();
  if (rules.empty() || rules.size() > static_cast<qsizetype>(kMaximumRules))
    return std::nullopt;
  for (const auto &rule_value : rules) {
    if (!rule_value.isArray())
      return std::nullopt;
    const auto matcher_values = rule_value.toArray();
    if (matcher_values.size() > static_cast<qsizetype>(kMaximumMatchers))
      return std::nullopt;
    Rule rule;
    for (const auto &matcher_value : matcher_values) {
      if (!matcher_value.isObject())
        return std::nullopt;
      const auto matcher_object = matcher_value.toObject();
      constexpr std::array matcher_keys{std::string_view("exact"),
                                        std::string_view("regex")};
      if (!exact_keys(matcher_object, matcher_keys) ||
          matcher_object.size() != 1)
        return std::nullopt;
      Matcher matcher;
      if (matcher_object.value("exact").isString()) {
        matcher.exact = matcher_object.value("exact").toString().toStdString();
        if (matcher.exact->size() > kMaximumArgumentBytes ||
            matcher.exact->find('\0') != std::string::npos)
          return std::nullopt;
      } else if (matcher_object.value("regex").isString()) {
        const auto source = matcher_object.value("regex").toString();
        if (source.isEmpty() || source.size() > 1024)
          return std::nullopt;
        matcher.expression = QRegularExpression(
            QStringLiteral("\\A(?:") + source + QStringLiteral(")\\z"),
            QRegularExpression::DontCaptureOption);
        if (!matcher.expression.isValid())
          return std::nullopt;
      } else {
        return std::nullopt;
      }
      rule.arguments.push_back(std::move(matcher));
    }
    policy.rules.push_back(std::move(rule));
  }
  return policy;
}

bool load_policy_directory(std::string_view root, uid_t trusted_uid,
                           bool required, std::vector<Policy> &policies) {
  if (!canonical_absolute_path(root))
    return false;
  struct stat metadata {};
  if (::lstat(std::string(root).c_str(), &metadata) < 0)
    return !required && errno == ENOENT;
  if (!secure_directory(metadata, trusted_uid))
    return false;
  std::vector<std::filesystem::path> names;
  for (const auto &entry : std::filesystem::directory_iterator(root)) {
    const auto name = entry.path().filename().string();
    if (name.ends_with(".policy"))
      names.push_back(entry.path());
    if (names.size() > kMaximumPolicies)
      return false;
  }
  std::ranges::sort(names);
  for (const auto &path : names) {
    auto descriptor = open_secure(path.string(), trusted_uid, false);
    const auto document = descriptor
                              ? read_bounded(descriptor.get(), kMaximumPolicyBytes)
                              : std::nullopt;
    auto policy = document ? parse_policy(*document, trusted_uid) : std::nullopt;
    if (!policy || std::ranges::any_of(policies, [&](const auto &existing) {
          return existing.profile == policy->profile;
        }))
      return false;
    policies.push_back(std::move(*policy));
  }
  return true;
}

std::optional<std::string> profile_from_scope(std::string_view scope) {
  QJsonParseError error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(scope.data(), static_cast<qsizetype>(scope.size())), &error);
  if (error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto object = document.object();
  if (object.size() != 1 || !object.value("profile").isString())
    return std::nullopt;
  const auto profile = object.value("profile").toString().toStdString();
  return canonical_component(profile) ? std::optional(profile) : std::nullopt;
}

struct Request final {
  std::uint64_t correlation = 0;
  std::string_view operation;
  std::string_view demand_scope;
  std::string command;
  std::vector<std::string> arguments;
};

std::optional<Request> decode_request(std::span<const std::byte> frame) {
  bool ok = true;
  const auto magic = u32(frame, 0, ok);
  const auto correlation = u64(frame, 8, ok);
  const auto body_size = u32(frame, 16, ok);
  if (!ok || frame.size() < kHeaderBytes || magic != kProtocolMagic ||
      std::to_integer<std::uint8_t>(frame[4]) != kProtocolVersion ||
      std::to_integer<std::uint8_t>(frame[5]) != kRequestType ||
      frame[6] != std::byte{0} || frame[7] != std::byte{0} ||
      correlation == 0 || body_size + kHeaderBytes != frame.size())
    return std::nullopt;
  std::size_t offset = kHeaderBytes;
  std::string_view adapter, contract, operation, demand_scope;
  if (!read_text(frame, offset, adapter) ||
      !read_text(frame, offset, contract))
    return std::nullopt;
  const auto abi = u32(frame, offset, ok);
  offset += 4;
  if (!ok || !read_text(frame, offset, operation) ||
      !read_text(frame, offset, demand_scope))
    return std::nullopt;
  const auto payload_size = u32(frame, offset, ok);
  offset += 4;
  if (!ok || offset + payload_size != frame.size() ||
      adapter != "bounded-command-execute" || abi != 1 || operation != "run" ||
      contract != omarchy::plugin_runtime::command_executor::kContractDigest)
    return std::nullopt;
  QJsonParseError json_error{};
  const auto document = QJsonDocument::fromJson(
      QByteArray(reinterpret_cast<const char *>(frame.data() + offset),
                 static_cast<qsizetype>(payload_size)),
      &json_error);
  if (json_error.error != QJsonParseError::NoError || !document.isObject())
    return std::nullopt;
  const auto object = document.object();
  constexpr std::array payload_keys{std::string_view("command"),
                                    std::string_view("arguments")};
  if (!exact_keys(object, payload_keys) || object.size() != 2 ||
      !object.value("command").isString() ||
      !object.value("arguments").isArray())
    return std::nullopt;
  Request request{.correlation = correlation,
                  .operation = operation,
                  .demand_scope = demand_scope,
                  .command = object.value("command").toString().toStdString(),
                  .arguments = {}};
  const auto arguments = object.value("arguments").toArray();
  if (arguments.size() > static_cast<qsizetype>(kMaximumMatchers))
    return std::nullopt;
  std::size_t total = request.command.size();
  for (const auto &argument : arguments) {
    if (!argument.isString())
      return std::nullopt;
    auto value = argument.toString().toStdString();
    if (value.size() > kMaximumArgumentBytes ||
        value.find('\0') != std::string::npos ||
        total > kMaximumTotalArgumentBytes - value.size())
      return std::nullopt;
    total += value.size();
    request.arguments.push_back(std::move(value));
  }
  return request;
}

bool matches(const Policy &policy, const Request &request) {
  if (request.command != policy.command)
    return false;
  return std::ranges::any_of(policy.rules, [&](const Rule &rule) {
    if (rule.arguments.size() != request.arguments.size())
      return false;
    for (std::size_t index = 0; index < rule.arguments.size(); ++index) {
      const auto &matcher = rule.arguments[index];
      const auto &argument = request.arguments[index];
      if (matcher.exact && argument != *matcher.exact)
        return false;
      if (!matcher.exact) {
        const auto text = QString::fromUtf8(argument);
        if (text.toUtf8().toStdString() != argument ||
            !matcher.expression.match(text).hasMatch())
          return false;
      }
    }
    return true;
  });
}

QByteArray fixed_home() {
  const auto *account = ::getpwuid(::getuid());
  if (!account || !account->pw_dir)
    return "/nonexistent";
  const QByteArray home(account->pw_dir);
  if (!home.startsWith('/') || home.contains('\0'))
    return "/nonexistent";
  return home;
}

struct CommandResult final {
  int exit_code = 126;
  QByteArray standard_output;
  QByteArray standard_error;
  bool timed_out = false;
};

bool append_pipe(Descriptor &descriptor, QByteArray &output,
                 std::size_t limit, bool &exceeded) {
  std::array<char, 4096> buffer{};
  while (descriptor) {
    const auto count = ::read(descriptor.get(), buffer.data(), buffer.size());
    if (count > 0) {
      const auto incoming = static_cast<std::size_t>(count);
      if (incoming > limit ||
          static_cast<std::size_t>(output.size()) > limit - incoming)
        exceeded = true;
      else
        output.append(buffer.data(), count);
      continue;
    }
    if (count == 0) {
      descriptor.reset();
      return true;
    }
    if (errno == EINTR)
      continue;
    if (errno == EAGAIN || errno == EWOULDBLOCK)
      return true;
    return false;
  }
  return true;
}

void kill_group(pid_t pid) {
  if (pid > 0)
    (void)::kill(-pid, SIGKILL);
}

CommandResult run(const Policy &policy, const Request &request) {
  CommandResult result;
  auto executable = open_secure(policy.executable_path, policy.trusted_uid, true);
  if (!executable) {
    result.standard_error = "command-unavailable";
    return result;
  }
  int stdout_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};
  if (::pipe2(stdout_pipe, O_CLOEXEC) < 0 ||
      ::pipe2(stderr_pipe, O_CLOEXEC) < 0) {
    if (stdout_pipe[0] >= 0) {
      ::close(stdout_pipe[0]);
      ::close(stdout_pipe[1]);
    }
    result.standard_error = "command-launch-failed";
    return result;
  }
  Descriptor stdout_read(stdout_pipe[0]);
  Descriptor stdout_write(stdout_pipe[1]);
  Descriptor stderr_read(stderr_pipe[0]);
  Descriptor stderr_write(stderr_pipe[1]);
  if (::fcntl(stdout_read.get(), F_SETFL,
              ::fcntl(stdout_read.get(), F_GETFL) | O_NONBLOCK) < 0 ||
      ::fcntl(stderr_read.get(), F_SETFL,
              ::fcntl(stderr_read.get(), F_GETFL) | O_NONBLOCK) < 0) {
    result.standard_error = "command-launch-failed";
    return result;
  }
  std::vector<char *> argv;
  argv.reserve(request.arguments.size() + 2);
  argv.push_back(const_cast<char *>(policy.command.c_str()));
  for (const auto &argument : request.arguments)
    argv.push_back(const_cast<char *>(argument.c_str()));
  argv.push_back(nullptr);
  const auto home = policy.account_home ? fixed_home() : QByteArray("/nonexistent");
  std::vector<QByteArray> environment_values{
      "PATH=/usr/bin", "LANG=C.UTF-8", "LC_ALL=C.UTF-8", "HOME=" + home};
  for (const auto &[name, value] : policy.environment)
    environment_values.push_back(name + "=" + value);
  std::vector<char *> environment;
  environment.reserve(environment_values.size() + 1);
  for (auto &value : environment_values)
    environment.push_back(value.data());
  environment.push_back(nullptr);

  const pid_t child = ::fork();
  if (child < 0) {
    result.standard_error = "command-launch-failed";
    return result;
  }
  if (child == 0) {
    (void)::setpgid(0, 0);
    (void)::umask(0077);
    stdout_read.reset();
    stderr_read.reset();
    const int null_fd = ::open("/dev/null", O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (::chdir("/") < 0 || null_fd < 0 ||
        ::dup2(null_fd, STDIN_FILENO) != STDIN_FILENO ||
        ::dup2(stdout_write.get(), STDOUT_FILENO) != STDOUT_FILENO ||
        ::dup2(stderr_write.get(), STDERR_FILENO) != STDERR_FILENO ||
        ::prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0 ||
        ::syscall(SYS_close_range, 3U, UINT_MAX, CLOSE_RANGE_CLOEXEC) < 0)
      _exit(126);
    (void)::syscall(SYS_execveat, executable.get(), "", argv.data(),
                    environment.data(), AT_EMPTY_PATH);
    _exit(127);
  }
  (void)::setpgid(child, child);
  stdout_write.reset();
  stderr_write.reset();
  const auto deadline = std::chrono::steady_clock::now() + policy.timeout;
  bool exceeded = false;
  int status = 0;
  bool reaped = false;
  while (stdout_read || stderr_read || !reaped) {
    if (std::chrono::steady_clock::now() >= deadline) {
      result.timed_out = true;
      kill_group(child);
    }
    std::array<pollfd, 2> poll_items{{
        {.fd = stdout_read.get(), .events = POLLIN, .revents = 0},
        {.fd = stderr_read.get(), .events = POLLIN, .revents = 0}}};
    (void)::poll(poll_items.data(), poll_items.size(), result.timed_out ? 0 : 25);
    if (!append_pipe(stdout_read, result.standard_output, policy.stdout_limit,
                     exceeded) ||
        !append_pipe(stderr_read, result.standard_error, policy.stderr_limit,
                     exceeded)) {
      exceeded = true;
    }
    if (exceeded)
      kill_group(child);
    if (!reaped) {
      const auto waited = ::waitpid(child, &status, WNOHANG);
      reaped = waited == child || (waited < 0 && errno == ECHILD);
    }
    if ((exceeded || result.timed_out) && !reaped) {
      while (::waitpid(child, &status, 0) < 0 && errno == EINTR) {}
      reaped = true;
    }
  }
  if (exceeded) {
    result.exit_code = 125;
    result.standard_output.clear();
    result.standard_error = "command-output-limit";
  } else if (result.timed_out) {
    result.exit_code = 124;
    result.standard_output.clear();
    result.standard_error = "command-timeout";
  } else if (WIFEXITED(status)) {
    result.exit_code = WEXITSTATUS(status);
  } else if (WIFSIGNALED(status)) {
    result.exit_code = 128 + WTERMSIG(status);
  }
  // A reviewed CLI is expected to finish its own helpers. Kill anything that
  // nevertheless retained the command process group before returning success.
  kill_group(child);
  return result;
}

QByteArray result_json(const CommandResult &result) {
  return QJsonDocument(QJsonObject{
                           {"exitCode", result.exit_code},
                           {"stdout", QString::fromUtf8(result.standard_output)},
                           {"stderr", QString::fromUtf8(result.standard_error)},
                           {"timedOut", result.timed_out}})
      .toJson(QJsonDocument::Compact);
}

bool send_response(std::uint64_t correlation, const QByteArray &payload) {
  if (payload.size() < 0 ||
      static_cast<std::size_t>(payload.size()) >
          kMaximumFrameBytes - kHeaderBytes - 1)
    return false;
  std::vector<std::byte> frame;
  frame.reserve(kHeaderBytes + 1 + static_cast<std::size_t>(payload.size()));
  put_u32(frame, kProtocolMagic);
  frame.push_back(static_cast<std::byte>(kProtocolVersion));
  frame.push_back(static_cast<std::byte>(kResponseType));
  frame.push_back(std::byte{0});
  frame.push_back(std::byte{0});
  put_u64(frame, correlation);
  put_u32(frame, static_cast<std::uint32_t>(payload.size() + 1));
  frame.push_back(std::byte{0});
  const auto bytes = std::as_bytes(
      std::span(payload.constData(), static_cast<std::size_t>(payload.size())));
  frame.insert(frame.end(), bytes.begin(), bytes.end());
  iovec part{.iov_base = frame.data(), .iov_len = frame.size()};
  msghdr message{};
  message.msg_iov = &part;
  message.msg_iovlen = 1;
  while (true) {
    const auto sent = ::sendmsg(3, &message, MSG_NOSIGNAL);
    if (sent == static_cast<ssize_t>(frame.size()))
      return true;
    if (sent < 0 && errno == EINTR)
      continue;
    return false;
  }
}

std::optional<uid_t> parse_uid(std::string_view value) {
  std::uint32_t parsed = 0;
  const auto [end, error] =
      std::from_chars(value.data(), value.data() + value.size(), parsed);
  if (error != std::errc{} || end != value.data() + value.size())
    return std::nullopt;
  return static_cast<uid_t>(parsed);
}

} // namespace

int main(int argc, char **argv) {
  bool validate_only = false;
#ifdef OMARCHY_COMMAND_EXECUTOR_TESTING
  validate_only = argc == 5 && std::string_view(argv[4]) == "--validate-only";
#endif
  if (argc != 4 && !validate_only)
    return 64;
  const auto trusted_uid = parse_uid(argv[3]);
  if (!trusted_uid)
    return 64;
  std::vector<Policy> policies;
  if (!load_policy_directory(argv[1], *trusted_uid, true, policies) ||
      !load_policy_directory(argv[2], *trusted_uid, false, policies)) {
#ifdef OMARCHY_COMMAND_EXECUTOR_TESTING
    std::cerr << "command executor test policy load rejected\n";
#endif
    return 78;
  }
  std::array<std::byte, kMaximumFrameBytes + 1> frame{};
  while (true) {
    iovec part{.iov_base = frame.data(), .iov_len = frame.size()};
    msghdr message{};
    message.msg_iov = &part;
    message.msg_iovlen = 1;
    const auto count = ::recvmsg(3, &message, MSG_TRUNC);
    if (count == 0)
      return 0;
    if (count < 0) {
      if (errno == EINTR)
        continue;
      return 1;
    }
    if (count > static_cast<ssize_t>(kMaximumFrameBytes))
      return 2;
    const auto request = decode_request(
        std::span(frame.data(), static_cast<std::size_t>(count)));
    if (!request)
      return 2;
    const auto requested_profile = profile_from_scope(request->demand_scope);
    const auto policy = requested_profile
                            ? std::ranges::find(policies, *requested_profile,
                                                &Policy::profile)
                            : policies.end();
    CommandResult result;
    if (policy == policies.end() || !matches(*policy, *request)) {
      result.standard_error = "command-rejected";
    } else if (validate_only) {
      result = {.exit_code = 0,
                .standard_output = "policy-accepted",
                .standard_error = {},
                .timed_out = false};
    } else {
      result = run(*policy, *request);
    }
    auto payload = result_json(result);
    if (static_cast<std::size_t>(payload.size()) >
        kMaximumFrameBytes - kHeaderBytes - 1) {
      result = {.exit_code = 125,
                .standard_output = {},
                .standard_error = "command-output-encoding-limit",
                .timed_out = false};
      payload = result_json(result);
    }
    if (!send_response(request->correlation, payload))
      return 3;
  }
}
