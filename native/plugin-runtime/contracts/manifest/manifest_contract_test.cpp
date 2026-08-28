#include "manifest_contract.hpp"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {

using omarchy::plugins::manifest::FailureReason;
using omarchy::plugins::manifest::Lifecycle;
using omarchy::plugins::manifest::RevisionState;

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
}

void lifecycle_contract() {
  const std::string revision_a(64, 'a');
  const std::string revision_b(64, 'b');
  const std::string failed_revision(64, 'c');
  Lifecycle lifecycle;
  expect_rejected([&] { lifecycle.validation_succeeded(true); },
                  "validation without staging succeeded");
  lifecycle.stage(revision_a);
  expect_rejected([&] { lifecycle.stage(revision_b); },
                  "second pending revision was staged");
  lifecycle.validation_succeeded(true);
  lifecycle.candidate_health_succeeded();
  require(lifecycle.active()->digest == revision_a &&
              lifecycle.active()->state == RevisionState::active,
          "first candidate did not activate");

  lifecycle.stage(revision_b);
  lifecycle.validation_succeeded(false);
  require(lifecycle.pending()->state == RevisionState::awaiting_grants,
          "missing grants did not block candidate");
  lifecycle.grants_changed(true);
  lifecycle.grants_changed(false);
  require(lifecycle.pending()->state == RevisionState::awaiting_grants &&
              lifecycle.pending()->failure == FailureReason::missing_grants,
          "grant revocation did not return candidate to awaiting-grants");
  lifecycle.grants_changed(true);
  lifecycle.candidate_health_failed();
  require(lifecycle.active()->digest == revision_a,
          "failed health replaced active revision");
  require(lifecycle.pending()->state == RevisionState::failed &&
              lifecycle.pending()->failure == FailureReason::health,
          "candidate health failure was not retained");
  lifecycle.discard_failed();

  lifecycle.stage(revision_b);
  lifecycle.validation_succeeded(true);
  lifecycle.candidate_health_succeeded();
  require(lifecycle.active()->digest == revision_b &&
              !lifecycle.history().empty(),
          "healthy update did not activate atomically");
  lifecycle.begin_rollback(revision_a, true);
  lifecycle.rollback_health_failed();
  require(lifecycle.active()->digest == revision_b,
          "failed rollback replaced active revision");
  lifecycle.discard_failed();
  lifecycle.begin_rollback(revision_a, true);
  lifecycle.rollback_health_succeeded();
  require(lifecycle.active()->digest == revision_a,
          "healthy rollback did not activate target");

  Lifecycle invalid;
  expect_rejected([&] { invalid.stage("not-a-sha256"); },
                  "noncanonical revision digest was staged");
  invalid.stage(failed_revision);
  invalid.validation_failed();
  require(invalid.pending()->failure == FailureReason::validation,
          "validation failure reason missing");
  expect_rejected([&] { invalid.candidate_health_succeeded(); },
                  "failed revision passed health");
  invalid.discard_failed();
  expect_rejected([&] { invalid.begin_rollback(failed_revision, true); },
                  "rollback without active revision succeeded");

  Lifecycle failed_history;
  failed_history.stage(revision_a);
  failed_history.validation_succeeded(true);
  failed_history.candidate_health_succeeded();
  failed_history.stage(failed_revision);
  failed_history.validation_succeeded(true);
  failed_history.candidate_health_failed();
  failed_history.discard_failed();
  expect_rejected([&] { failed_history.begin_rollback(failed_revision, true); },
                  "failed candidate became an eligible rollback target");
}

} // namespace

int main() {
  try {
    const std::filesystem::path fixtures = MANIFEST_FIXTURE_ROOT;
    parser_contract(fixtures);
    digest_contract(fixtures);
    lifecycle_contract();
    std::cout << "manifest v2 and lifecycle contract: PASS\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "manifest-contract-test: " << error.what() << '\n';
    return 1;
  }
}
