#include "manifest_contract.hpp"

#include <algorithm>
#include <array>
#include <bit>
#include <charconv>
#include <cstddef>
#include <fstream>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <system_error>
#include <tuple>
#include <type_traits>
#include <variant>

namespace omarchy::plugins::manifest {
namespace {

using namespace std::literals;

constexpr std::size_t kMaximumManifestBytes = 1024 * 1024;
constexpr std::size_t kMaximumStringBytes = 16 * 1024;
constexpr std::size_t kMaximumDepth = 32;
constexpr std::size_t kMaximumContainerEntries = 256;
constexpr std::size_t kMaximumFiles = 4096;
constexpr std::uint64_t kMaximumTreeBytes = 64ULL * 1024ULL * 1024ULL;

[[noreturn]] void fail(std::string_view message) {
  throw std::runtime_error(std::string(message));
}

void require(bool condition, std::string_view message) {
  if (!condition) {
    fail(message);
  }
}

using Object = std::map<std::string, struct Json, std::less<>>;
using Array = std::vector<struct Json>;

struct Json {
  using Value = std::variant<std::nullptr_t, bool, std::int64_t, std::string,
                             Array, Object>;
  Value value;
};

void append_utf8(std::string &output, std::uint32_t codepoint) {
  require(codepoint <= 0x10ffff &&
              !(codepoint >= 0xd800 && codepoint <= 0xdfff),
          "invalid Unicode scalar value");
  if (codepoint <= 0x7f) {
    output.push_back(static_cast<char>(codepoint));
  } else if (codepoint <= 0x7ff) {
    output.push_back(static_cast<char>(0xc0 | (codepoint >> 6)));
    output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
  } else if (codepoint <= 0xffff) {
    output.push_back(static_cast<char>(0xe0 | (codepoint >> 12)));
    output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
    output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
  } else {
    output.push_back(static_cast<char>(0xf0 | (codepoint >> 18)));
    output.push_back(static_cast<char>(0x80 | ((codepoint >> 12) & 0x3f)));
    output.push_back(static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f)));
    output.push_back(static_cast<char>(0x80 | (codepoint & 0x3f)));
  }
}

class Parser {
public:
  explicit Parser(std::string_view input) : input_(input) {
    require(input.size() <= kMaximumManifestBytes, "manifest is too large");
  }

  Json parse() {
    skip_space();
    Json result = value(0);
    skip_space();
    require(position_ == input_.size(), "trailing JSON data");
    return result;
  }

private:
  void skip_space() {
    while (position_ < input_.size() &&
           (input_[position_] == ' ' || input_[position_] == '\n' ||
            input_[position_] == '\r' || input_[position_] == '\t')) {
      ++position_;
    }
  }

  char take() {
    require(position_ < input_.size(), "unexpected end of JSON");
    return input_[position_++];
  }

  bool consume(char expected) {
    if (position_ < input_.size() && input_[position_] == expected) {
      ++position_;
      return true;
    }
    return false;
  }

  void literal(std::string_view expected) {
    require(input_.substr(position_, expected.size()) == expected,
            "invalid JSON literal");
    position_ += expected.size();
  }

  std::uint32_t hex4() {
    require(position_ + 4 <= input_.size(), "truncated Unicode escape");
    std::uint32_t value = 0;
    for (int index = 0; index < 4; ++index) {
      const char character = input_[position_++];
      value <<= 4;
      if (character >= '0' && character <= '9') {
        value |= static_cast<std::uint32_t>(character - '0');
      } else if (character >= 'a' && character <= 'f') {
        value |= static_cast<std::uint32_t>(character - 'a' + 10);
      } else if (character >= 'A' && character <= 'F') {
        value |= static_cast<std::uint32_t>(character - 'A' + 10);
      } else {
        fail("invalid Unicode escape");
      }
    }
    return value;
  }

  std::string string() {
    require(take() == '"', "expected JSON string");
    std::string output;
    while (true) {
      const unsigned char character = static_cast<unsigned char>(take());
      if (character == '"') {
        require(output.size() <= kMaximumStringBytes,
                "JSON string is too long");
        return output;
      }
      require(character >= 0x20, "control character in JSON string");
      if (character == '\\') {
        const char escaped = take();
        switch (escaped) {
        case '"':
          output.push_back('"');
          break;
        case '\\':
          output.push_back('\\');
          break;
        case '/':
          output.push_back('/');
          break;
        case 'b':
          output.push_back('\b');
          break;
        case 'f':
          output.push_back('\f');
          break;
        case 'n':
          output.push_back('\n');
          break;
        case 'r':
          output.push_back('\r');
          break;
        case 't':
          output.push_back('\t');
          break;
        case 'u': {
          std::uint32_t codepoint = hex4();
          if (codepoint >= 0xd800 && codepoint <= 0xdbff) {
            require(take() == '\\' && take() == 'u',
                    "missing low Unicode surrogate");
            const std::uint32_t low = hex4();
            require(low >= 0xdc00 && low <= 0xdfff,
                    "invalid low Unicode surrogate");
            codepoint = 0x10000 + ((codepoint - 0xd800) << 10) + (low - 0xdc00);
          }
          append_utf8(output, codepoint);
          break;
        }
        default:
          fail("invalid JSON escape");
        }
      } else if (character < 0x80) {
        output.push_back(static_cast<char>(character));
      } else {
        const std::size_t start = position_ - 1;
        std::size_t length = 0;
        std::uint32_t codepoint = 0;
        if ((character & 0xe0) == 0xc0) {
          length = 2;
          codepoint = character & 0x1f;
        } else if ((character & 0xf0) == 0xe0) {
          length = 3;
          codepoint = character & 0x0f;
        } else if ((character & 0xf8) == 0xf0) {
          length = 4;
          codepoint = character & 0x07;
        } else {
          fail("invalid UTF-8 lead byte");
        }
        require(start + length <= input_.size(), "truncated UTF-8 sequence");
        for (std::size_t index = 1; index < length; ++index) {
          const auto continuation =
              static_cast<unsigned char>(input_[start + index]);
          require((continuation & 0xc0) == 0x80, "invalid UTF-8 continuation");
          codepoint = (codepoint << 6) | (continuation & 0x3f);
        }
        require((length != 2 || codepoint >= 0x80) &&
                    (length != 3 || codepoint >= 0x800) &&
                    (length != 4 || codepoint >= 0x10000),
                "overlong UTF-8 sequence");
        append_utf8(output, codepoint);
        position_ = start + length;
      }
      require(output.size() <= kMaximumStringBytes, "JSON string is too long");
    }
  }

  Json number() {
    const std::size_t start = position_;
    consume('-');
    require(position_ < input_.size(), "truncated JSON number");
    if (consume('0')) {
      require(position_ == input_.size() || input_[position_] < '0' ||
                  input_[position_] > '9',
              "leading zero in JSON number");
    } else {
      require(input_[position_] >= '1' && input_[position_] <= '9',
              "invalid JSON number");
      while (position_ < input_.size() && input_[position_] >= '0' &&
             input_[position_] <= '9') {
        ++position_;
      }
    }
    require(position_ == input_.size() ||
                (input_[position_] != '.' && input_[position_] != 'e' &&
                 input_[position_] != 'E'),
            "non-integer JSON numbers are unsupported");
    std::int64_t result = 0;
    const auto parsed = std::from_chars(input_.data() + start,
                                        input_.data() + position_, result);
    require(parsed.ec == std::errc() && parsed.ptr == input_.data() + position_,
            "JSON integer is out of range");
    return Json{result};
  }

  Json array(std::size_t depth) {
    require(take() == '[', "expected JSON array");
    Array result;
    skip_space();
    if (consume(']'))
      return Json{std::move(result)};
    while (true) {
      require(result.size() < kMaximumContainerEntries,
              "JSON array has too many entries");
      skip_space();
      result.push_back(value(depth + 1));
      skip_space();
      if (consume(']'))
        return Json{std::move(result)};
      require(consume(','), "expected comma in JSON array");
    }
  }

  Json object(std::size_t depth) {
    require(take() == '{', "expected JSON object");
    Object result;
    skip_space();
    if (consume('}'))
      return Json{std::move(result)};
    while (true) {
      require(result.size() < kMaximumContainerEntries,
              "JSON object has too many members");
      skip_space();
      require(position_ < input_.size() && input_[position_] == '"',
              "expected JSON object key");
      std::string key = string();
      skip_space();
      require(consume(':'), "expected colon after JSON object key");
      skip_space();
      auto [unused, inserted] =
          result.emplace(std::move(key), value(depth + 1));
      (void)unused;
      require(inserted, "duplicate JSON object key");
      skip_space();
      if (consume('}'))
        return Json{std::move(result)};
      require(consume(','), "expected comma in JSON object");
    }
  }

  Json value(std::size_t depth) {
    require(depth <= kMaximumDepth, "JSON nesting is too deep");
    require(position_ < input_.size(), "missing JSON value");
    switch (input_[position_]) {
    case 'n':
      literal("null");
      return Json{nullptr};
    case 't':
      literal("true");
      return Json{true};
    case 'f':
      literal("false");
      return Json{false};
    case '"':
      return Json{string()};
    case '[':
      return array(depth);
    case '{':
      return object(depth);
    default:
      if (input_[position_] == '-' ||
          (input_[position_] >= '0' && input_[position_] <= '9')) {
        return number();
      }
      fail("invalid JSON value");
    }
  }

  std::string_view input_;
  std::size_t position_ = 0;
};

void encode_string(std::string_view value, std::string &output) {
  constexpr char hex[] = "0123456789abcdef";
  output.push_back('"');
  for (const unsigned char character : value) {
    switch (character) {
    case '"':
      output += "\\\"";
      break;
    case '\\':
      output += "\\\\";
      break;
    case '\b':
      output += "\\b";
      break;
    case '\f':
      output += "\\f";
      break;
    case '\n':
      output += "\\n";
      break;
    case '\r':
      output += "\\r";
      break;
    case '\t':
      output += "\\t";
      break;
    default:
      if (character < 0x20) {
        output += "\\u00";
        output.push_back(hex[character >> 4]);
        output.push_back(hex[character & 0x0f]);
      } else {
        output.push_back(static_cast<char>(character));
      }
    }
  }
  output.push_back('"');
}

void encode(const Json &json, std::string &output) {
  std::visit(
      [&output](const auto &value) {
        using T = std::decay_t<decltype(value)>;
        if constexpr (std::is_same_v<T, std::nullptr_t>) {
          output += "null";
        } else if constexpr (std::is_same_v<T, bool>) {
          output += value ? "true" : "false";
        } else if constexpr (std::is_same_v<T, std::int64_t>) {
          output += std::to_string(value);
        } else if constexpr (std::is_same_v<T, std::string>) {
          encode_string(value, output);
        } else if constexpr (std::is_same_v<T, Array>) {
          output.push_back('[');
          for (std::size_t index = 0; index < value.size(); ++index) {
            if (index != 0)
              output.push_back(',');
            encode(value[index], output);
          }
          output.push_back(']');
        } else {
          output.push_back('{');
          bool first = true;
          for (const auto &[key, item] : value) {
            if (!first)
              output.push_back(',');
            first = false;
            encode_string(key, output);
            output.push_back(':');
            encode(item, output);
          }
          output.push_back('}');
        }
      },
      json.value);
}

std::string canonical(const Json &json) {
  std::string output;
  encode(json, output);
  return output;
}

const Object &as_object(const Json &json, std::string_view field) {
  const auto *value = std::get_if<Object>(&json.value);
  require(value != nullptr, std::string(field) + " must be an object");
  return *value;
}

const Array &as_array(const Json &json, std::string_view field) {
  const auto *value = std::get_if<Array>(&json.value);
  require(value != nullptr, std::string(field) + " must be an array");
  return *value;
}

const std::string &as_string(const Json &json, std::string_view field) {
  const auto *value = std::get_if<std::string>(&json.value);
  require(value != nullptr, std::string(field) + " must be a string");
  return *value;
}

std::int64_t as_integer(const Json &json, std::string_view field) {
  const auto *value = std::get_if<std::int64_t>(&json.value);
  require(value != nullptr, std::string(field) + " must be an integer");
  return *value;
}

const Json &required(const Object &object, std::string_view key) {
  const auto found = object.find(key);
  require(found != object.end(),
          std::string("missing required field ") + std::string(key));
  return found->second;
}

void known_keys(const Object &object,
                std::initializer_list<std::string_view> allowed,
                std::string_view context) {
  for (const auto &[key, unused] : object) {
    (void)unused;
    require(std::find(allowed.begin(), allowed.end(), key) != allowed.end(),
            std::string("unknown ") + std::string(context) + " field " + key);
  }
}

void bounded_text(std::string_view value, std::size_t maximum,
                  std::string_view field) {
  require(!value.empty() && value.size() <= maximum,
          std::string(field) + " has invalid length");
  require(value.find('\0') == std::string_view::npos,
          std::string(field) + " contains NUL");
}

bool valid_identifier(std::string_view value) {
  if (value.empty() || value.size() > 128)
    return false;
  bool previous_separator = true;
  for (const unsigned char character : value) {
    const bool alphanumeric = (character >= 'a' && character <= 'z') ||
                              (character >= '0' && character <= '9');
    const bool separator =
        character == '.' || character == '-' || character == '_';
    if (!alphanumeric && !separator)
      return false;
    if (separator && previous_separator)
      return false;
    previous_separator = separator;
  }
  return !previous_separator && value.front() >= 'a' && value.front() <= 'z';
}

bool safe_relative_path(std::string_view value) {
  if (value.empty() || value.size() > 4096 || value.front() == '/' ||
      value.find('\\') != std::string_view::npos ||
      value.find('\0') != std::string_view::npos) {
    return false;
  }
  std::filesystem::path path(value);
  for (const auto &part : path) {
    if (part == "." || part == ".." || part.empty())
      return false;
  }
  return path.lexically_normal().generic_string() == value;
}

class Sha256 {
public:
  void update(std::span<const std::byte> input) {
    bit_count_ += static_cast<std::uint64_t>(input.size()) * 8;
    for (const std::byte item : input) {
      buffer_[buffer_size_++] = std::to_integer<std::uint8_t>(item);
      if (buffer_size_ == buffer_.size()) {
        transform(buffer_.data());
        buffer_size_ = 0;
      }
    }
  }

  void update(std::string_view input) {
    update(std::as_bytes(std::span(input.data(), input.size())));
  }

  std::array<std::byte, 32> finish() {
    const std::uint64_t original_bits = bit_count_;
    const std::byte marker{0x80};
    update(std::span(&marker, 1));
    const std::byte zero{0};
    while (buffer_size_ != 56)
      update(std::span(&zero, 1));
    std::array<std::byte, 8> length{};
    for (std::size_t index = 0; index < length.size(); ++index) {
      length[index] = std::byte((original_bits >> ((7 - index) * 8)) & 0xff);
    }
    update(length);
    std::array<std::byte, 32> output{};
    for (std::size_t word = 0; word < state_.size(); ++word) {
      for (std::size_t byte = 0; byte < 4; ++byte) {
        output[word * 4 + byte] =
            std::byte((state_[word] >> ((3 - byte) * 8)) & 0xff);
      }
    }
    return output;
  }

private:
  static constexpr std::array<std::uint32_t, 64> constants_ = {
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
      0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
      0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
      0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
      0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

  static std::uint32_t choose(std::uint32_t x, std::uint32_t y,
                              std::uint32_t z) {
    return (x & y) ^ (~x & z);
  }
  static std::uint32_t majority(std::uint32_t x, std::uint32_t y,
                                std::uint32_t z) {
    return (x & y) ^ (x & z) ^ (y & z);
  }

  void transform(const std::uint8_t *block) {
    std::array<std::uint32_t, 64> words{};
    for (std::size_t index = 0; index < 16; ++index) {
      words[index] = (static_cast<std::uint32_t>(block[index * 4]) << 24) |
                     (static_cast<std::uint32_t>(block[index * 4 + 1]) << 16) |
                     (static_cast<std::uint32_t>(block[index * 4 + 2]) << 8) |
                     static_cast<std::uint32_t>(block[index * 4 + 3]);
    }
    for (std::size_t index = 16; index < words.size(); ++index) {
      const auto s0 = std::rotr(words[index - 15], 7) ^
                      std::rotr(words[index - 15], 18) ^
                      (words[index - 15] >> 3);
      const auto s1 = std::rotr(words[index - 2], 17) ^
                      std::rotr(words[index - 2], 19) ^
                      (words[index - 2] >> 10);
      words[index] = words[index - 16] + s0 + words[index - 7] + s1;
    }
    auto a = state_[0];
    auto b = state_[1];
    auto c = state_[2];
    auto d = state_[3];
    auto e = state_[4];
    auto f = state_[5];
    auto g = state_[6];
    auto h = state_[7];
    for (std::size_t index = 0; index < words.size(); ++index) {
      const auto upper_e =
          std::rotr(e, 6) ^ std::rotr(e, 11) ^ std::rotr(e, 25);
      const auto first =
          h + upper_e + choose(e, f, g) + constants_[index] + words[index];
      const auto upper_a =
          std::rotr(a, 2) ^ std::rotr(a, 13) ^ std::rotr(a, 22);
      const auto second = upper_a + majority(a, b, c);
      h = g;
      g = f;
      f = e;
      e = d + first;
      d = c;
      c = b;
      b = a;
      a = first + second;
    }
    state_[0] += a;
    state_[1] += b;
    state_[2] += c;
    state_[3] += d;
    state_[4] += e;
    state_[5] += f;
    state_[6] += g;
    state_[7] += h;
  }

  std::array<std::uint32_t, 8> state_{0x6a09e667, 0xbb67ae85, 0x3c6ef372,
                                      0xa54ff53a, 0x510e527f, 0x9b05688c,
                                      0x1f83d9ab, 0x5be0cd19};
  std::array<std::uint8_t, 64> buffer_{};
  std::size_t buffer_size_ = 0;
  std::uint64_t bit_count_ = 0;
};

std::string hex(std::span<const std::byte> bytes) {
  constexpr char digits[] = "0123456789abcdef";
  std::string output;
  output.reserve(bytes.size() * 2);
  for (const std::byte item : bytes) {
    const auto value = std::to_integer<unsigned int>(item);
    output.push_back(digits[value >> 4]);
    output.push_back(digits[value & 0x0f]);
  }
  return output;
}

void hash_u64(Sha256 &hash, std::uint64_t value) {
  std::array<std::byte, 8> bytes{};
  for (std::size_t index = 0; index < bytes.size(); ++index) {
    bytes[index] = std::byte((value >> ((7 - index) * 8)) & 0xff);
  }
  hash.update(bytes);
}

void hash_field(Sha256 &hash, std::string_view value) {
  hash_u64(hash, value.size());
  hash.update(value);
}

std::string fingerprint_requests(const std::vector<CapabilityRequest> &input) {
  auto requests = input;
  std::sort(requests.begin(), requests.end(),
            [](const auto &left, const auto &right) {
              return std::tie(left.capability, left.required,
                              left.canonical_scope) <
                     std::tie(right.capability, right.required,
                              right.canonical_scope);
            });
  Sha256 hash;
  hash.update("OMARCHY-PLUGIN-REQUESTS-V1\0"sv);
  hash_u64(hash, requests.size());
  for (const auto &request : requests) {
    const std::byte requirement{request.required ? std::uint8_t{1}
                                                 : std::uint8_t{0}};
    hash.update(std::span(&requirement, 1));
    hash_field(hash, request.capability);
    hash_field(hash, request.canonical_scope);
  }
  return hex(hash.finish());
}

std::string read_file(const std::filesystem::path &path, std::uint64_t limit) {
  std::ifstream stream(path, std::ios::binary);
  require(stream.good(), "cannot open plugin file");
  std::string output;
  std::array<char, 8192> chunk{};
  while (stream) {
    stream.read(chunk.data(), static_cast<std::streamsize>(chunk.size()));
    const auto count = stream.gcount();
    require(output.size() + static_cast<std::size_t>(count) <= limit,
            "plugin file exceeds tree limit");
    output.append(chunk.data(), static_cast<std::size_t>(count));
  }
  require(stream.eof(), "cannot read plugin file");
  return output;
}

void require_pending(const std::optional<RevisionStatus> &pending,
                     RevisionState expected, std::string_view operation) {
  require(pending.has_value() && pending->state == expected,
          std::string("invalid lifecycle transition: ") +
              std::string(operation));
}

bool valid_digest(std::string_view digest) {
  return digest.size() == 64 &&
         std::all_of(digest.begin(), digest.end(),
                     [](const unsigned char item) {
                       return (item >= '0' && item <= '9') ||
                              (item >= 'a' && item <= 'f');
                     });
}

} // namespace

ManifestV2 parse_manifest_v2(std::string_view bytes) {
  const Json document = Parser(bytes).parse();
  const Object &root = as_object(document, "manifest");
  known_keys(root,
             {"schemaVersion", "id", "name", "version", "description",
              "runtime", "surfaces", "permissions"},
             "manifest");
  require(as_integer(required(root, "schemaVersion"), "schemaVersion") == 2,
          "unsupported schemaVersion");

  ManifestV2 result;
  result.id = as_string(required(root, "id"), "id");
  require(valid_identifier(result.id), "invalid plugin id");
  result.name = as_string(required(root, "name"), "name");
  bounded_text(result.name, 256, "name");
  result.version = as_string(required(root, "version"), "version");
  bounded_text(result.version, 128, "version");
  if (const auto found = root.find("description"); found != root.end()) {
    result.description = as_string(found->second, "description");
    require(result.description.size() <= 4096, "description is too long");
  }

  const Object &runtime = as_object(required(root, "runtime"), "runtime");
  known_keys(runtime, {"apiVersion", "qml", "worker"}, "runtime");
  const auto api_version =
      as_integer(required(runtime, "apiVersion"), "runtime.apiVersion");
  require(api_version == 1, "unsupported runtime.apiVersion");
  result.runtime.api_version = static_cast<std::uint32_t>(api_version);
  result.runtime.qml = as_string(required(runtime, "qml"), "runtime.qml");
  require(safe_relative_path(result.runtime.qml), "unsafe runtime.qml path");
  if (const auto found = runtime.find("worker"); found != runtime.end()) {
    const Array &worker = as_array(found->second, "runtime.worker");
    require(!worker.empty() && worker.size() <= 64,
            "runtime.worker has invalid length");
    for (const auto &argument : worker) {
      auto value = as_string(argument, "runtime.worker argument");
      require(value.size() <= 4096 && value.find('\0') == std::string::npos,
              "invalid runtime.worker argument");
      result.runtime.worker.push_back(std::move(value));
    }
    require(safe_relative_path(result.runtime.worker.front()),
            "unsafe runtime.worker executable path");
  }

  const Json &surfaces = required(root, "surfaces");
  (void)as_object(surfaces, "surfaces");
  result.canonical_surfaces = canonical(surfaces);

  const Object &permissions =
      as_object(required(root, "permissions"), "permissions");
  known_keys(permissions, {"required", "optional"}, "permissions");
  std::set<std::string, std::less<>> capabilities;
  for (const auto &[key, is_required] :
       std::array<std::pair<std::string_view, bool>, 2>{
           {{"required", true}, {"optional", false}}}) {
    const Array &requests = as_array(required(permissions, key), key);
    require(requests.size() <= 128, "too many capability requests");
    for (const auto &item : requests) {
      Object request = as_object(item, "capability request");
      const std::string capability =
          as_string(required(request, "capability"), "capability");
      require(valid_identifier(capability), "invalid capability id");
      require(capabilities.insert(capability).second,
              "duplicate capability request");
      const std::string reason =
          as_string(required(request, "reason"), "reason");
      bounded_text(reason, 1024, "reason");
      request.erase("capability");
      request.erase("reason");
      result.requests.push_back({.capability = capability,
                                 .reason = reason,
                                 .canonical_scope = canonical(Json{request}),
                                 .required = is_required});
    }
  }
  result.canonical_json = canonical(document);
  return result;
}

ContentIdentity identify_tree(const std::filesystem::path &root,
                              const ManifestV2 &manifest) {
  struct FileEntry {
    std::string relative;
    std::filesystem::path path;
    bool executable = false;
  };
  std::error_code error;
  require(std::filesystem::is_directory(root, error) && !error,
          "plugin root is not a directory");
  std::vector<FileEntry> files;
  std::uint64_t total_size = 0;
  for (std::filesystem::recursive_directory_iterator
           iterator(root, std::filesystem::directory_options::none, error),
       end;
       iterator != end; iterator.increment(error)) {
    require(!error, "cannot enumerate plugin tree");
    const auto relative =
        std::filesystem::relative(iterator->path(), root, error);
    require(!error, "cannot resolve plugin path");
    if (*relative.begin() == ".git") {
      if (iterator->is_directory(error))
        iterator.disable_recursion_pending();
      require(!error, "cannot inspect .git entry");
      continue;
    }
    const auto status = iterator->symlink_status(error);
    require(!error, "cannot inspect plugin tree entry");
    require(!std::filesystem::is_symlink(status), "symlink in plugin tree");
    if (std::filesystem::is_directory(status))
      continue;
    require(std::filesystem::is_regular_file(status),
            "special file in plugin tree");
    const auto size = iterator->file_size(error);
    require(!error && size <= kMaximumTreeBytes - total_size,
            "plugin tree is too large");
    total_size += size;
    const auto permissions = status.permissions();
    const bool executable =
        (permissions & (std::filesystem::perms::owner_exec |
                        std::filesystem::perms::group_exec |
                        std::filesystem::perms::others_exec)) !=
        std::filesystem::perms::none;
    files.push_back({.relative = relative.generic_string(),
                     .path = iterator->path(),
                     .executable = executable});
    require(files.size() <= kMaximumFiles, "plugin tree has too many files");
  }
  std::sort(files.begin(), files.end(),
            [](const auto &left, const auto &right) {
              return left.relative < right.relative;
            });
  require(!files.empty(), "plugin tree is empty");

  const auto has_file = [&files](std::string_view path) {
    const auto found =
        std::lower_bound(files.begin(), files.end(), path,
                         [](const auto &entry, std::string_view wanted) {
                           return entry.relative < wanted;
                         });
    return found != files.end() && found->relative == path;
  };
  const auto is_executable_file = [&files](std::string_view path) {
    const auto found =
        std::lower_bound(files.begin(), files.end(), path,
                         [](const auto &entry, std::string_view wanted) {
                           return entry.relative < wanted;
                         });
    return found != files.end() && found->relative == path && found->executable;
  };
  require(has_file("manifest.json"), "plugin tree has no manifest.json");
  require(has_file(manifest.runtime.qml), "runtime.qml does not exist");
  if (!manifest.runtime.worker.empty()) {
    require(is_executable_file(manifest.runtime.worker.front()),
            "runtime.worker executable is missing or not executable");
  }

  Sha256 tree;
  tree.update("OMARCHY-PLUGIN-TREE-V1\0"sv);
  hash_u64(tree, files.size());
  std::string manifest_bytes;
  std::uint64_t actual_total = 0;
  for (const auto &[relative, path, executable] : files) {
    const auto bytes = read_file(path, kMaximumTreeBytes);
    require(bytes.size() <= kMaximumTreeBytes - actual_total,
            "plugin tree changed beyond its size limit while hashing");
    actual_total += bytes.size();
    hash_field(tree, relative);
    const std::byte mode{executable ? std::uint8_t{1} : std::uint8_t{0}};
    tree.update(std::span(&mode, 1));
    hash_field(tree, bytes);
    if (relative == "manifest.json")
      manifest_bytes = bytes;
  }
  require(parse_manifest_v2(manifest_bytes) == manifest,
          "manifest model does not match the hashed manifest.json");
  return {.tree_sha256 = hex(tree.finish()),
          .manifest_sha256 = sha256_hex(manifest_bytes),
          .request_sha256 = fingerprint_requests(manifest.requests)};
}

std::string requested_capability_fingerprint(
    const std::vector<CapabilityRequest> &requests) {
  return fingerprint_requests(requests);
}

std::string sha256_hex(std::span<const std::byte> bytes) {
  Sha256 hash;
  hash.update(bytes);
  return hex(hash.finish());
}

std::string sha256_hex(std::string_view bytes) {
  return sha256_hex(std::as_bytes(std::span(bytes.data(), bytes.size())));
}

void Lifecycle::stage(std::string digest) {
  require(valid_digest(digest), "cannot stage a noncanonical digest");
  require(!pending_.has_value(), "a revision is already pending");
  require(!active_.has_value() || active_->digest != digest,
          "active revision cannot be restaged");
  pending_ = RevisionStatus{.digest = std::move(digest),
                            .state = RevisionState::staged,
                            .failure = std::nullopt};
}

void Lifecycle::validation_succeeded(bool required_grants_present) {
  require_pending(pending_, RevisionState::staged, "validation success");
  pending_->state = required_grants_present ? RevisionState::candidate
                                            : RevisionState::awaiting_grants;
  pending_->failure = required_grants_present
                          ? std::nullopt
                          : std::optional(FailureReason::missing_grants);
}

void Lifecycle::validation_failed() {
  require_pending(pending_, RevisionState::staged, "validation failure");
  pending_->state = RevisionState::failed;
  pending_->failure = FailureReason::validation;
}

void Lifecycle::grants_changed(bool required_grants_present) {
  require(pending_.has_value() &&
              (pending_->state == RevisionState::awaiting_grants ||
               pending_->state == RevisionState::candidate),
          "invalid lifecycle transition: grant change");
  pending_->state = required_grants_present ? RevisionState::candidate
                                            : RevisionState::awaiting_grants;
  pending_->failure = required_grants_present
                          ? std::nullopt
                          : std::optional(FailureReason::missing_grants);
}

void Lifecycle::candidate_health_succeeded() {
  require_pending(pending_, RevisionState::candidate,
                  "candidate health success");
  if (active_.has_value())
    history_.push_back(*active_);
  pending_->state = RevisionState::active;
  pending_->failure.reset();
  active_ = std::move(pending_);
  pending_.reset();
}

void Lifecycle::candidate_health_failed() {
  require_pending(pending_, RevisionState::candidate,
                  "candidate health failure");
  pending_->state = RevisionState::failed;
  pending_->failure = FailureReason::health;
}

void Lifecycle::begin_rollback(std::string digest,
                               bool required_grants_present) {
  require(active_.has_value(), "rollback requires an active revision");
  require(!pending_.has_value(), "rollback requires no pending revision");
  require(valid_digest(digest), "rollback digest is not canonical");
  require(required_grants_present, "rollback target lacks required grants");
  const auto found = std::find_if(
      history_.begin(), history_.end(), [&digest](const auto &item) {
        return item.digest == digest && item.state == RevisionState::active &&
               !item.failure.has_value();
      });
  require(found != history_.end(), "rollback target is not retained");
  pending_ = RevisionStatus{.digest = std::move(digest),
                            .state = RevisionState::rollback_candidate,
                            .failure = std::nullopt};
}

void Lifecycle::rollback_health_succeeded() {
  require_pending(pending_, RevisionState::rollback_candidate,
                  "rollback health success");
  history_.push_back(*active_);
  pending_->state = RevisionState::active;
  active_ = std::move(pending_);
  pending_.reset();
}

void Lifecycle::rollback_health_failed() {
  require_pending(pending_, RevisionState::rollback_candidate,
                  "rollback health failure");
  pending_->state = RevisionState::failed;
  pending_->failure = FailureReason::rollback_health;
}

void Lifecycle::discard_failed() {
  require_pending(pending_, RevisionState::failed, "discard failed revision");
  history_.push_back(*pending_);
  pending_.reset();
}

const std::optional<RevisionStatus> &Lifecycle::active() const {
  return active_;
}
const std::optional<RevisionStatus> &Lifecycle::pending() const {
  return pending_;
}
const std::vector<RevisionStatus> &Lifecycle::history() const {
  return history_;
}

} // namespace omarchy::plugins::manifest
