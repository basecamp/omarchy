#include "manifest_contract.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <sys/stat.h>

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

void expect_rejected(const std::function<void()> &operation,
                     std::string_view message) {
  bool rejected = false;
  try {
    operation();
  } catch (const std::runtime_error &) {
    rejected = true;
  }
  require(rejected, message);
}

std::string read(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "cannot read fixture");
  return {std::istreambuf_iterator<char>(input),
          std::istreambuf_iterator<char>()};
}

void parser_contract(const std::filesystem::path &fixtures) {
  const auto valid_root = fixtures / "valid-minimal";
  const auto manifest = omarchy::plugins::manifest::parse_manifest_v2(
      read(valid_root / "manifest.json"));
  require(manifest.id == "org.example.status", "manifest id was not parsed");
  require(manifest.runtime.api_version == 1 &&
              manifest.runtime.qml == "ui/Status.qml",
          "runtime was not parsed");
  require(manifest.requests.size() == 2 && manifest.requests[0].required &&
              !manifest.requests[1].required,
          "permission classes were not preserved");
  require(manifest.requests[0].canonical_scope == "{\"quotaBytes\":1048576}",
          "scope did not canonicalize");

  const auto dynamic = omarchy::plugins::manifest::parse_manifest_v2(
      R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"local.status","definitionGeneration":7,"definitionDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operations":["status.read"],"resource":4,"reason":"status"}],"optional":[]}})");
  require(dynamic.requests.size() == 1 &&
              dynamic.requests[0].definition_generation == 7 &&
              dynamic.requests[0].definition_digest == std::string(64, 'a') &&
              dynamic.requests[0].operations ==
                  std::vector<std::string>{"status.read"} &&
              dynamic.requests[0].canonical_scope == "{\"resource\":4}",
          "dynamic definition reference was not preserved");

  const auto with_sidecars = omarchy::plugins::manifest::parse_manifest_v2(
      R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","sidecars":[{"name":"indexer","command":["bin/indexer","--socket","/run/plugin/indexer.sock"]},{"name":"state-helper","command":["bin/state-helper"]}]} ,"surfaces":{},"permissions":{"required":[],"optional":[]}})");
  require(with_sidecars.runtime.sidecars.size() == 2 &&
              with_sidecars.runtime.sidecars[0].name == "indexer" &&
              with_sidecars.runtime.sidecars[0].command ==
                  std::vector<std::string>{"bin/indexer", "--socket",
                                           "/run/plugin/indexer.sock"},
          "declared sidecars were not preserved exactly");
  const auto multi_surface = omarchy::plugins::manifest::parse_manifest_v2(
      R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","surfaceQml":{"atlas":"Atlas.qml","barWidget":"BarWidget.qml"}},"surfaces":{"atlas":{},"barWidget":{}},"permissions":{"required":[],"optional":[]}})");
  require(multi_surface.runtime.surface_qml.size() == 2 &&
              multi_surface.runtime.surface_qml[0].surface == "atlas" &&
              multi_surface.runtime.surface_qml[0].qml == "Atlas.qml" &&
              multi_surface.runtime.surface_qml[1].surface == "barWidget" &&
              multi_surface.runtime.surface_qml[1].qml == "BarWidget.qml",
          "per-surface QML entries were not preserved exactly");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","surfaceQml":{"missing":"Other.qml"}},"surfaces":{"atlas":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "QML entry for an undeclared surface was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","surfaceQml":{"atlas":"../Other.qml"}},"surfaces":{"atlas":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "escaping per-surface QML entry was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","sidecars":[{"name":"escape","command":["../host-tool"]}]},"surfaces":{},"permissions":{"required":[],"optional":[]}})");
      },
      "escaping sidecar executable was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","sidecars":[{"name":"same","command":["bin/one"]},{"name":"same","command":["bin/two"]}]},"surfaces":{},"permissions":{"required":[],"optional":[]}})");
      },
      "duplicate sidecar identity was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"local.status","definitionGeneration":7,"operations":["status.read"],"reason":"status"}],"optional":[]}})");
      },
      "incomplete dynamic definition reference was accepted");

  expect_rejected(
      [&] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            read(fixtures / "invalid-duplicate/manifest.json"));
      },
      "duplicate manifest key was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","i\u0064":"a.c","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[],"optional":[]}})");
      },
      "escaped duplicate manifest key was accepted");
  expect_rejected(
      [&] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            read(fixtures / "invalid-entrypoint/manifest.json"));
      },
      "escaping entry point was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[],"optional":[]},"typo":true})");
      },
      "unknown manifest field was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"scale":1.5},"permissions":{"required":[],"optional":[]}})");
      },
      "non-integer scope number was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"A.B","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[],"optional":[]}})");
      },
      "noncanonical plugin id was accepted");
}

void digest_contract(const std::filesystem::path &fixtures) {
  using omarchy::plugins::manifest::identify_tree;
  using omarchy::plugins::manifest::parse_manifest_v2;
  using omarchy::plugins::manifest::sha256_hex;

  require(
      sha256_hex("") ==
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "SHA-256 empty golden mismatch");
  require(
      sha256_hex("abc") ==
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
      "SHA-256 abc golden mismatch");
  require(
      sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
      "SHA-256 multi-block golden mismatch");

  const auto root = fixtures / "valid-minimal";
  const auto bytes = read(root / "manifest.json");
  const auto manifest = parse_manifest_v2(bytes);
  const auto identity = identify_tree(root, manifest);
  require(identity.tree_sha256 == TREE_SHA256_GOLDEN,
          "tree SHA-256 golden mismatch: " + identity.tree_sha256);
  require(identity.manifest_sha256 == MANIFEST_SHA256_GOLDEN,
          "manifest SHA-256 golden mismatch: " + identity.manifest_sha256);
  require(identity.request_sha256 == REQUEST_SHA256_GOLDEN,
          "request SHA-256 golden mismatch: " + identity.request_sha256);

  const auto reordered = parse_manifest_v2(
      R"({"permissions":{"optional":[{"reason":"different words","categories":["timer"],"capability":"notifications.send"}],"required":[{"reason":"also different","quotaBytes":1048576,"capability":"storage.private"}]},"surfaces":{"barWidget":{"defaultSection":"right","role":"bar-embedded"}},"runtime":{"qml":"ui/Status.qml","apiVersion":1},"version":"2.0.0","name":"Example Status","id":"org.example.status","schemaVersion":2})");
  expect_rejected(
      [&] { (void)identify_tree(root, reordered); },
      "stale manifest model was accepted for a different tree manifest");
  require(omarchy::plugins::manifest::requested_capability_fingerprint(
              reordered.requests) == identity.request_sha256,
          "key order or reason changed request fingerprint");
  const auto expanded = parse_manifest_v2(
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml"},"surfaces":{},"permissions":{"required":[{"capability":"storage.private","quotaBytes":2097152,"reason":"Save"}],"optional":[{"capability":"notifications.send","categories":["timer"],"reason":"Notify"}]}})");
  require(omarchy::plugins::manifest::requested_capability_fingerprint(
              expanded.requests) != identity.request_sha256,
          "expanded scope did not change request fingerprint");

  const auto temporary =
      std::filesystem::temp_directory_path() /
      ("omarchy-manifest-contract-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  struct RemoveTree {
    std::filesystem::path path;
    ~RemoveTree() {
      std::error_code ignored;
      std::filesystem::remove_all(path, ignored);
    }
  } cleanup{temporary};
  std::filesystem::copy(root, temporary,
                        std::filesystem::copy_options::recursive);
  const auto copied_manifest =
      parse_manifest_v2(read(temporary / "manifest.json"));
  const auto copied_identity = identify_tree(temporary, copied_manifest);
  require(copied_identity == identity, "copied tree identity changed");
  std::filesystem::create_directories(temporary / ".git");
  std::ofstream(temporary / ".git/config") << "untrusted metadata\n";
  expect_rejected([&] { (void)identify_tree(temporary, copied_manifest); },
                  ".git content was excluded from path identity");
  std::filesystem::remove_all(temporary / ".git");
  const auto qml = temporary / "ui/Status.qml";
  std::filesystem::permissions(qml, std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::add);
  require(identify_tree(temporary, copied_manifest).tree_sha256 !=
              identity.tree_sha256,
          "executable mode did not change tree identity");
  std::filesystem::permissions(qml, std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::remove);
  std::filesystem::create_symlink("ui/Status.qml", temporary / "alias.qml");
  expect_rejected([&] { (void)identify_tree(temporary, copied_manifest); },
                  "symlink in content tree was accepted");

  std::filesystem::remove(temporary / "alias.qml");
  require(mkfifo((temporary / "host-channel").c_str(), 0600) == 0,
          "special-file fixture could not be created");
  expect_rejected([&] { (void)identify_tree(temporary, copied_manifest); },
                  "special file in content tree was accepted");
  std::filesystem::remove(temporary / "host-channel");
  {
    std::ofstream surface(temporary / "ui/BarWidget.qml",
                          std::ios::binary | std::ios::trunc);
    surface << "import QtQuick\nItem {}\n";
  }
  const std::string multi_surface_manifest_bytes =
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml","surfaceQml":{"barWidget":"ui/BarWidget.qml"}},"surfaces":{"barWidget":{"role":"bar-embedded"}},"permissions":{"required":[],"optional":[]}})";
  {
    std::ofstream manifest_output(temporary / "manifest.json",
                                  std::ios::binary | std::ios::trunc);
    manifest_output << multi_surface_manifest_bytes;
  }
  const auto multi_surface_manifest =
      parse_manifest_v2(multi_surface_manifest_bytes);
  (void)identify_tree(temporary, multi_surface_manifest);
  std::filesystem::remove(temporary / "ui/BarWidget.qml");
  expect_rejected(
      [&] { (void)identify_tree(temporary, multi_surface_manifest); },
      "missing per-surface QML entry was accepted");
  {
    std::ofstream manifest_output(temporary / "manifest.json",
                                  std::ios::binary | std::ios::trunc);
    manifest_output << bytes;
  }
  {
    std::ofstream oversized(temporary / "oversized.bin",
                            std::ios::binary | std::ios::trunc);
    oversized.seekp(64ULL * 1024ULL * 1024ULL);
    oversized.put('\0');
  }
  expect_rejected([&] { (void)identify_tree(temporary, copied_manifest); },
                  "oversized content tree was accepted");
  std::filesystem::remove(temporary / "oversized.bin");
  std::filesystem::create_directories(temporary / "bin");
  {
    std::ofstream sidecar(temporary / "bin/helper", std::ios::binary);
    sidecar << "sidecar fixture\n";
  }
  std::filesystem::permissions(temporary / "bin/helper",
                               std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::add);
  const std::string sidecar_manifest_bytes =
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml","sidecars":[{"name":"helper","command":["bin/helper","--serve"]}]},"surfaces":{},"permissions":{"required":[],"optional":[]}})";
  {
    std::ofstream manifest_output(temporary / "manifest.json",
                                  std::ios::binary | std::ios::trunc);
    manifest_output << sidecar_manifest_bytes;
  }
  const auto sidecar_manifest = parse_manifest_v2(sidecar_manifest_bytes);
  (void)identify_tree(temporary, sidecar_manifest);
  std::filesystem::permissions(temporary / "bin/helper",
                               std::filesystem::perms::owner_exec,
                               std::filesystem::perm_options::remove);
  expect_rejected([&] { (void)identify_tree(temporary, sidecar_manifest); },
                  "non-executable declared sidecar was accepted");
}

void mutation_contract(const std::filesystem::path &fixtures) {
  const auto seed = read(fixtures / "valid-minimal/manifest.json");
  std::size_t accepted = 0;
  std::size_t rejected = 0;
  for (std::size_t iteration = 0; iteration < 2048; ++iteration) {
    std::string candidate = seed;
    const std::size_t offset =
        (iteration * 2654435761ULL + 17ULL) % candidate.size();
    candidate[offset] = static_cast<char>(
        static_cast<unsigned char>(candidate[offset]) ^
        static_cast<unsigned char>(1U << (iteration % 8)));
    try {
      const auto parsed =
          omarchy::plugins::manifest::parse_manifest_v2(candidate);
      const auto reparsed = omarchy::plugins::manifest::parse_manifest_v2(
          parsed.canonical_json);
      require(parsed == reparsed,
              "accepted manifest mutation was not canonically stable");
      ++accepted;
    } catch (const std::runtime_error &) {
      ++rejected;
    }
  }
  require(accepted > 0 && rejected > 0,
          "manifest mutation corpus did not exercise both parser outcomes");
}

} // namespace

int main() {
  try {
    const std::filesystem::path fixtures = MANIFEST_FIXTURE_ROOT;
    parser_contract(fixtures);
    digest_contract(fixtures);
    mutation_contract(fixtures);
    std::cout << "manifest v2 contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "manifest-contract-test: " << error.what() << '\n';
    return 1;
  }
}
