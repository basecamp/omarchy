#include "manifest_contract.hpp"

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

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
  require(manifest.surface_names == std::vector<std::string>{"barWidget"},
          "declared shared-QML surface names were not retained");
  require(manifest.requests.size() == 2 && manifest.requests[0].required &&
              !manifest.requests[1].required,
          "permission classes were not preserved");
  require(manifest.requests[0].canonical_scope == "{\"quotaBytes\":1048576}",
          "scope did not canonicalize");

  const auto product_settings =
      omarchy::plugins::manifest::parse_manifest_v2(
          R"({"schemaVersion":2,"id":"robzolkos.github","name":"GitHub","version":"0.4.0","author":"Rob Zolkos","license":"MIT","homepage":"https://example.test/plugin","repository":"https://example.test/repository","keywords":["github","inbox"],"runtime":{"apiVersion":1,"qml":"Panel.qml"},"surfaces":{},"settings":{"defaults":{"enabled":false,"mode":"Owned","refreshIntervalSec":900},"schema":[{"key":"refreshIntervalSec","type":"integer","label":"Refresh interval","min":60,"max":3600,"step":60,"defaultValue":900},{"key":"mode","type":"enum","label":"Scope","options":["Owned","All"],"defaultValue":"Owned"},{"key":"enabled","type":"boolean","label":"Enabled","defaultValue":false}]},"permissions":{"required":[],"optional":[]}})");
  require(product_settings.author == "Rob Zolkos" &&
              product_settings.license == "MIT" &&
              product_settings.homepage == "https://example.test/plugin" &&
              product_settings.repository ==
                  "https://example.test/repository" &&
              product_settings.keywords ==
                  std::vector<std::string>{"github", "inbox"},
          "standard metadata was not retained");
  require(product_settings.settings.schema.size() == 3 &&
              product_settings.settings.canonical_defaults ==
                  R"({"enabled":false,"mode":"Owned","refreshIntervalSec":900})" &&
              omarchy::plugins::manifest::validate_settings_entry(
                  product_settings, product_settings.settings.defaults),
          "settings were not canonicalized and schema validated");
  auto invalid_settings = product_settings.settings.defaults;
  invalid_settings["refreshIntervalSec"] = std::int64_t{30};
  require(!omarchy::plugins::manifest::validate_settings_entry(
              product_settings, invalid_settings),
          "out-of-range settings entry was accepted");
  auto off_step_settings = product_settings.settings.defaults;
  off_step_settings["refreshIntervalSec"] = std::int64_t{901};
  require(omarchy::plugins::manifest::validate_settings_entry(
              product_settings, off_step_settings),
          "in-range integer was rejected because it is off the UI step");
  invalid_settings = product_settings.settings.defaults;
  invalid_settings["mode"] = std::string("Other");
  require(!omarchy::plugins::manifest::validate_settings_entry(
              product_settings, invalid_settings),
          "unknown enum settings value was accepted");
  invalid_settings = product_settings.settings.defaults;
  invalid_settings["enabled"] = std::string("false");
  require(!omarchy::plugins::manifest::validate_settings_entry(
              product_settings, invalid_settings),
          "wrong-typed settings entry was accepted");
  invalid_settings = product_settings.settings.defaults;
  invalid_settings["unknown"] = true;
  require(!omarchy::plugins::manifest::validate_settings_entry(
              product_settings, invalid_settings),
          "unknown settings entry key was accepted");
  invalid_settings = product_settings.settings.defaults;
  invalid_settings.erase("enabled");
  require(!omarchy::plugins::manifest::validate_settings_entry(
              product_settings, invalid_settings),
          "missing settings entry key was accepted");

  const auto off_step_default =
      omarchy::plugins::manifest::parse_manifest_v2(
          R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"settings":{"defaults":{"value":2},"schema":[{"key":"value","type":"integer","label":"Value","min":1,"max":5,"step":2,"defaultValue":2}]},"permissions":{"required":[],"optional":[]}})");
  require(off_step_default.settings.defaults.at("value") ==
              omarchy::plugins::manifest::SettingValue(std::int64_t{2}),
          "in-range default was rejected because it is off the UI step");

  for (const auto malformed : {
           R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"settings":{"defaults":{"mode":"Unknown"},"schema":[{"key":"mode","type":"enum","label":"Mode","options":["Known"],"defaultValue":"Unknown"}]},"permissions":{"required":[],"optional":[]}})",
           R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"settings":{"defaults":{"enabled":false},"schema":[{"key":"enabled","type":"boolean","label":"Enabled","defaultValue":false,"typo":true}]},"permissions":{"required":[],"optional":[]}})"}) {
    expect_rejected(
        [malformed] {
          (void)omarchy::plugins::manifest::parse_manifest_v2(malformed);
        },
        "malformed settings schema was accepted");
  }

  const auto dynamic = omarchy::plugins::manifest::parse_manifest_v2(
      R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"local.status","definitionGeneration":7,"definitionDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operations":["status.read"],"resource":4,"reason":"status"}],"optional":[]}})");
  require(dynamic.requests.size() == 1 &&
              dynamic.requests[0].definition_generation == 7 &&
              dynamic.requests[0].definition_digest == std::string(64, 'a') &&
              dynamic.requests[0].operations ==
                  std::vector<std::string>{"status.read"} &&
              dynamic.requests[0].canonical_scope == "{\"resource\":4}",
          "dynamic definition reference was not preserved");

  const auto fixed_operations =
      omarchy::plugins::manifest::parse_manifest_v2(
          R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"service.fake-status","resourceIds":[1],"operations":["list","acknowledge"],"reason":"status"}],"optional":[]}})");
  require(fixed_operations.requests.size() == 1 &&
              fixed_operations.requests[0].operations.empty() &&
              fixed_operations.requests[0].canonical_scope ==
                  R"({"operations":["acknowledge","list"],"resourceIds":[1]})",
          "fixed capability operations escaped the canonical scope");

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
              multi_surface.surface_names ==
                  std::vector<std::string>{"atlas", "barWidget"} &&
              multi_surface.runtime.surface_qml[0].surface == "atlas" &&
              multi_surface.runtime.surface_qml[0].qml == "Atlas.qml" &&
              multi_surface.runtime.surface_qml[1].surface == "barWidget" &&
              multi_surface.runtime.surface_qml[1].qml == "BarWidget.qml",
          "per-surface QML entries were not preserved exactly");
  const std::string maximum_surface_name(64, 'X');
  const auto maximum_surface =
      omarchy::plugins::manifest::parse_manifest_v2(
          std::string(R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{")") +
          maximum_surface_name +
          R"(":{}},"permissions":{"required":[],"optional":[]}})");
  require(maximum_surface.surface_names ==
              std::vector<std::string>{maximum_surface_name},
          "maximum wire-safe surface name was rejected");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","surfaceQml":{"missing":"Other.qml"}},"surfaces":{"atlas":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "QML entry for an undeclared surface was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml","surfaceQml":{"atlas":"Atlas.qml"}},"surfaces":{"atlas":{},"barWidget":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "partial per-surface QML mapping was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"Panel.Widget":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "dotted surface name outside the wire contract was accepted");
  expect_rejected(
      [] {
        const std::string name(65, 'X');
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            std::string(R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{")") +
            name +
            R"(":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "65-byte surface name outside the wire contract was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"bad\u0000name":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "NUL surface name outside the wire contract was accepted");
  expect_rejected(
      [] {
        (void)omarchy::plugins::manifest::parse_manifest_v2(
            R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{"a":{},"b":{},"c":{},"d":{},"e":{},"f":{},"g":{},"h":{},"i":{}},"permissions":{"required":[],"optional":[]}})");
      },
      "more than eight declared surfaces were accepted");
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
  using omarchy::plugins::manifest::identify_tree_contents;
  using omarchy::plugins::manifest::parse_manifest_v2;
  using omarchy::plugins::manifest::sha256_hex;

  const auto make_contents = [](std::string manifest_bytes,
                                bool qml_executable = false) {
    omarchy::plugins::manifest::TreeContents contents;
    contents.add({.relative = "manifest.json",
                  .bytes = std::move(manifest_bytes)});
    contents.add({.relative = "ui/Status.qml",
                  .bytes = "import QtQuick\n\nItem { }\n",
                  .executable = qml_executable});
    return contents;
  };

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
  const auto identity = identify_tree_contents(make_contents(bytes), manifest);
  require(identity.tree_sha256 == TREE_SHA256_GOLDEN,
          "tree SHA-256 golden mismatch: " + identity.tree_sha256);
  require(identity.manifest_sha256 == MANIFEST_SHA256_GOLDEN,
          "manifest SHA-256 golden mismatch: " + identity.manifest_sha256);
  require(identity.request_sha256 == REQUEST_SHA256_GOLDEN,
          "request SHA-256 golden mismatch: " + identity.request_sha256);

  const auto reordered = parse_manifest_v2(
      R"({"permissions":{"optional":[{"reason":"different words","categories":["timer"],"capability":"notifications.send"}],"required":[{"reason":"also different","quotaBytes":1048576,"capability":"storage.private"}]},"surfaces":{"barWidget":{"defaultSection":"right","role":"bar-embedded"}},"runtime":{"qml":"ui/Status.qml","apiVersion":1},"version":"2.0.0","name":"Example Status","id":"org.example.status","schemaVersion":2})");
  expect_rejected(
      [&] { (void)identify_tree_contents(make_contents(bytes), reordered); },
      "stale manifest model was accepted for a different tree manifest");
  require(omarchy::plugins::manifest::requested_capability_fingerprint(
              reordered.requests) == identity.request_sha256,
          "key order or reason changed request fingerprint");
  const auto expanded = parse_manifest_v2(
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml"},"surfaces":{},"permissions":{"required":[{"capability":"storage.private","quotaBytes":2097152,"reason":"Save"}],"optional":[{"capability":"notifications.send","categories":["timer"],"reason":"Notify"}]}})");
  require(omarchy::plugins::manifest::requested_capability_fingerprint(
              expanded.requests) != identity.request_sha256,
          "expanded scope did not change request fingerprint");

  require(identify_tree_contents(make_contents(bytes, true), manifest)
                  .tree_sha256 != identity.tree_sha256,
          "executable mode did not change tree identity");

  expect_rejected(
      [&] {
        auto contents = make_contents(bytes);
        contents.add({.relative = ".git/config", .bytes = "metadata"});
      },
      ".git content was accepted by canonical tree contents");
  expect_rejected(
      [&] {
        auto contents = make_contents(bytes);
        contents.add({.relative = "../escape", .bytes = "content"});
      },
      "escaping content path was accepted");

  const std::string multi_surface_manifest_bytes =
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml","surfaceQml":{"barWidget":"ui/BarWidget.qml"}},"surfaces":{"barWidget":{"role":"bar-embedded"}},"permissions":{"required":[],"optional":[]}})";
  const auto multi_surface_manifest =
      parse_manifest_v2(multi_surface_manifest_bytes);
  auto multi_surface_contents = make_contents(multi_surface_manifest_bytes);
  multi_surface_contents.add(
      {.relative = "ui/BarWidget.qml", .bytes = "import QtQuick\nItem {}\n"});
  (void)identify_tree_contents(std::move(multi_surface_contents),
                               multi_surface_manifest);
  expect_rejected(
      [&] {
        (void)identify_tree_contents(
            make_contents(multi_surface_manifest_bytes),
            multi_surface_manifest);
      },
      "missing per-surface QML entry was accepted");

  const std::string sidecar_manifest_bytes =
      R"({"schemaVersion":2,"id":"org.example.status","name":"Example Status","version":"2.0.0","runtime":{"apiVersion":1,"qml":"ui/Status.qml","sidecars":[{"name":"helper","command":["bin/helper","--serve"]}]},"surfaces":{},"permissions":{"required":[],"optional":[]}})";
  const auto sidecar_manifest = parse_manifest_v2(sidecar_manifest_bytes);
  auto sidecar_contents = make_contents(sidecar_manifest_bytes);
  sidecar_contents.add({.relative = "bin/helper",
                        .bytes = "sidecar fixture\n",
                        .executable = true});
  (void)identify_tree_contents(std::move(sidecar_contents), sidecar_manifest);
  expect_rejected(
      [&] {
        auto contents = make_contents(sidecar_manifest_bytes);
        contents.add({.relative = "bin/helper",
                      .bytes = "sidecar fixture\n",
                      .executable = false});
        (void)identify_tree_contents(std::move(contents), sidecar_manifest);
      },
                  "non-executable declared sidecar was accepted");
}

void request_fingerprint_v2_contract() {
  using omarchy::plugins::manifest::canonical_capability_requests;
  using omarchy::plugins::manifest::parse_manifest_v2;
  using omarchy::plugins::manifest::requested_capability_fingerprint;

  const auto original = parse_manifest_v2(
      R"({"schemaVersion":2,"id":"a.b","name":"x","version":"1","runtime":{"apiVersion":1,"qml":"Main.qml"},"surfaces":{},"permissions":{"required":[{"capability":"local.status","definitionGeneration":7,"definitionDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operations":["status.write","status.read"],"resource":4,"reason":"status"}],"optional":[{"capability":"notifications.send","categories":["timer"],"reason":"notify"}]}})");
  const auto equivalent = parse_manifest_v2(
      R"({"permissions":{"optional":[{"reason":"different display text","categories":["timer"],"capability":"notifications.send"}],"required":[{"reason":"also different","resource":4,"operations":["status.read","status.write"],"definitionDigest":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","definitionGeneration":7,"capability":"local.status"}]},"surfaces":{},"runtime":{"qml":"Main.qml","apiVersion":1},"version":"1","name":"x","id":"a.b","schemaVersion":2})");

  const auto fingerprint = requested_capability_fingerprint(original.requests);
  require(requested_capability_fingerprint(original.requests) == fingerprint,
          "unchanged request set did not retain its V2 fingerprint");
  require(requested_capability_fingerprint(equivalent.requests) == fingerprint,
          "equivalent request or operation ordering changed V2 fingerprint");
  auto reordered_requests = original.requests;
  std::reverse(reordered_requests.begin(), reordered_requests.end());
  require(requested_capability_fingerprint(reordered_requests) == fingerprint,
          "request set ordering changed V2 fingerprint");
  const auto canonical =
      canonical_capability_requests(std::move(reordered_requests));
  require(canonical.size() == 2 &&
              canonical[0].capability == "local.status" &&
              canonical[0].operations ==
                  std::vector<std::string>{"status.read", "status.write"} &&
              canonical[1].capability == "notifications.send",
          "public request index order diverged from fingerprint tuples");

  auto changed_generation = original.requests;
  ++changed_generation.front().definition_generation;
  require(requested_capability_fingerprint(changed_generation) != fingerprint,
          "definition generation did not affect V2 request fingerprint");

  auto changed_digest = original.requests;
  changed_digest.front().definition_digest = std::string(64, 'b');
  require(requested_capability_fingerprint(changed_digest) != fingerprint,
          "definition digest did not affect V2 request fingerprint");

  auto changed_operations = original.requests;
  changed_operations.front().operations.back() = "status.watch";
  require(requested_capability_fingerprint(changed_operations) != fingerprint,
          "operations did not affect V2 request fingerprint");
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
    request_fingerprint_v2_contract();
    mutation_contract(fixtures);
    std::cout << "manifest v2 contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "manifest-contract-test: " << error.what() << '\n';
    return 1;
  }
}
