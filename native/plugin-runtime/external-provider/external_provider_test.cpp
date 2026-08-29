#include "external_provider.hpp"
#include "provider_registration.hpp"
#include "capability_definition_loader.hpp"
#include <array>
#include <climits>
#include <fstream>
#include <stdexcept>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
using namespace omarchy::plugins;
namespace {
void require(bool v, std::string_view m) {
  if (!v)
    throw std::runtime_error(std::string(m));
}
definitions::Digest digest(char c) {
  return definitions::Digest(std::string(64, c));
}
bool rx(int fd, std::span<std::byte> s, std::span<const std::byte> &f) {
  auto n = recv(fd, s.data(), s.size(), 0);
  if (n <= 0)
    return false;
  f = std::span<const std::byte>(s).first(n);
  return true;
}
bool tx(int fd, std::span<const std::byte> f) {
  return write(fd, f.data(), f.size()) == static_cast<ssize_t>(f.size());
}
struct AuthorizationProbe {
  unsigned calls = 0;
  unsigned deny_after = UINT_MAX;
};
struct Scope final
    : omarchy::plugin_runtime::launcher::ResourceScopeController {
  unsigned attached = 0;
  unsigned killed = 0;
  unsigned removed = 0;
  bool probe(std::string &) override { return true; }
  bool attach(std::string_view, pid_t, pid_t,
              const omarchy::plugin_runtime::sandbox::SandboxPlan &,
              std::chrono::milliseconds, std::string &) override {
    ++attached;
    return true;
  }
  void kill(std::string_view) noexcept override { ++killed; }
  void remove(std::string_view) noexcept override { ++removed; }
};
bool authorized(const definitions::DynamicAuthorizationContext &,
                void *context) noexcept {
  auto &probe = *static_cast<AuthorizationProbe *>(context);
  return probe.calls++ < probe.deny_after;
}
bool adapter_available(std::string_view, const definitions::Digest &,
                       std::uint32_t, void *) noexcept {
  return true;
}
definitions::DynamicScopeRelation exact_scope(
    const definitions::CapabilityDefinition &, std::string_view left,
    std::string_view right, void *) noexcept {
  return left == right ? definitions::DynamicScopeRelation::equal
                       : definitions::DynamicScopeRelation::incomparable;
}
} // namespace
int main(int argc, char **) {
  if (argc == 2) {
    std::array<std::byte, external_provider::kMaximumFrameBytes> b{};
    std::span<const std::byte> f;
    if (!rx(3, b, f) || !tx(3, f)) {
      return 70;
    }
    if (!rx(3, b, f)) {
      return 71;
    }
    external_provider::RequestFrame q{};
    if (!external_provider::decode_request(f, q) ||
        q.service_id.view() != "local.fake-provider") {
      return 72;
    }
    if (q.operation.view() == "crash")
      return 88;
    if (q.operation.view() == "timeout")
      for (;;)
        pause();
    if (q.operation.view() == "descendant") {
      const pid_t child = fork();
      if (child == 0)
        for (;;)
          pause();
      if (child > 0)
        for (;;)
          pause();
      return 89;
    }
    if (q.operation.view() != "status")
      return 72;
    std::array<std::byte, definitions::kMaximumDynamicPayloadBytes>
        payload_copy{};
    std::ranges::copy(q.payload, payload_copy.begin());
    external_provider::ReplyFrame p{
        q.correlation, q.host_nonce,
        std::span(payload_copy).first(q.payload.size())};
    size_t n = 0;
    if (!external_provider::encode_reply(p, b, n) ||
        !tx(3, std::span(b).first(n))) {
      return 73;
    }
    return 0;
  }
  const auto self = std::filesystem::canonical("/proc/self/exe");
  std::ifstream stream(self, std::ios::binary);
  const std::string bytes((std::istreambuf_iterator<char>(stream)), {});
  auto scope = std::make_shared<Scope>();
  auto launcher = omarchy::plugin_runtime::launcher::Supervisor::forTestOnly(
      "/usr/bin/bwrap", self.string(), scope);
  external_provider::Registration r{
      .service_id = definitions::Name("local.fake-provider"),
      .adapter = {.adapter_class = definitions::Name("fake-bounded-harness"),
                  .implementation_digest = digest('d'),
                  .abi_version = 1},
      .executable = self,
      .executable_digest = definitions::Digest(manifest::sha256_hex(bytes)),
      .expected_uid = static_cast<std::uint32_t>(getuid()),
      .protocol_version = 2,
      .launcher = &launcher};
  permissions::ActivationBinding binding{
      .plugin = permissions::PluginId("org.example.plugin"),
      .revision = digest('b'),
      .policy_fingerprint = digest('c'),
      .generation = 2};
  const std::array payload{std::byte{0x2a}, std::byte{0x2b}};
  definitions::AuthorizedDynamicRequest q{
      .authorization = {.binding = binding,
                        .definition = {.canonical_name = definitions::Name(
                                           "local.my-harness"),
                                       .definition_generation = 1,
                                       .definition_digest = digest('e')},
                        .grant_epoch = 4},
      .operation = "status",
      .demand_scope = "profile=my-harness-v1",
      .payload = payload};
  std::array<std::byte, 16> out{};
  size_t n = 0;
  std::array<std::byte, external_provider::kMaximumFrameBytes> preflight{};
  std::array<std::byte, external_provider::kNonceBytes> preflight_nonce{};
  external_provider::RequestFrame preflight_request{
      r.service_id,
      r.adapter,
      q.authorization,
      definitions::Name(q.operation),
      definitions::CanonicalScope(q.demand_scope),
      q.payload,
      1,
      preflight_nonce};
  require(external_provider::encode_request(preflight_request, preflight, n),
          "preflight encode failed");
  const auto result =
      external_provider::invoke(r, q, out, n, std::chrono::seconds(1), 4);
  require(result == external_provider::Result::completed && n == 2 &&
              out[0] == payload[0],
          "authenticated provider E2E failed: " +
              std::to_string(static_cast<int>(result)));
  require(external_provider::invoke(r, q, out, n, std::chrono::seconds(1), 5) ==
              external_provider::Result::revoked,
          "stale epoch reached provider");
  const auto dynamic_adapter = external_provider::compose_dynamic_adapter(r);
  n = 0;
  require(dynamic_adapter.binding == r.adapter &&
              dynamic_adapter.dispatch != nullptr &&
              dynamic_adapter.dispatch(q, out, n, dynamic_adapter.context) &&
              n == payload.size(),
          "trusted registration did not compose into a live dynamic adapter");
  auto hostile = q;
  hostile.operation = "crash";
  require(external_provider::invoke(r, hostile, out, n,
                                    std::chrono::milliseconds(250), 4) ==
              external_provider::Result::crashed,
          "crashed provider was not reported");
  hostile.operation = "timeout";
  require(external_provider::invoke(r, hostile, out, n,
                                    std::chrono::milliseconds(100), 4) ==
              external_provider::Result::timeout,
          "hung provider was not bounded");
  hostile.operation = "descendant";
  const auto descendant_result = external_provider::invoke(
      r, hostile, out, n, std::chrono::milliseconds(100), 4);
  require(descendant_result == external_provider::Result::crashed ||
              descendant_result == external_provider::Result::timeout,
          "descendant attempt escaped provider teardown");
  require(scope->attached >= 5 && scope->removed == scope->attached &&
              scope->killed >= 1,
          "provider crash/timeout did not tear down its complete scope: " +
              std::to_string(scope->attached) + "/" +
              std::to_string(scope->removed) + "/" +
              std::to_string(scope->killed));
  std::array audit_template{'/', 't', 'm', 'p', '/', 'o', 'm', 'a', 'r', 'c',
                            'h', 'y', '-', 'e', 'x', 't', '-', 'a', 'u', 'd',
                            'i', 't', '-', 'X', 'X', 'X', 'X', 'X', 'X', '\0'};
  const auto *audit_root = mkdtemp(audit_template.data());
  require(audit_root != nullptr, "audit fixture creation failed");
  audit::AuditStore audit_store(audit_root, {});
  require(audit_store.recover().ok(), "audit fixture recovery failed");
  AuthorizationProbe authorization{};
  external_provider::InvocationGuard guard{.audit = &audit_store,
                                           .correlation = 41,
                                           .still_authorized = authorized,
                                           .authorization_context =
                                               &authorization};
  require(external_provider::invoke_audited(
              r, q, out, n, std::chrono::seconds(1), 4, guard) ==
              external_provider::Result::completed,
          "audited provider invocation failed");
  audit::Query audit_query{};
  audit_query.maximum_results = 8;
  const auto records = audit_store.query(audit_query);
  require(records.status.ok() && records.records.size() == 2 &&
              records.records[0].event ==
                  permissions::AuditEvent::operation_decided &&
              records.records[1].event ==
                  permissions::AuditEvent::operation_completed &&
              records.records[0].correlation == 41 &&
              records.records[1].correlation == 41,
          "decision and terminal audit records were not durable");
  authorization = {.deny_after = 1};
  guard.correlation = 42;
  require(external_provider::invoke_audited(
              r, q, out, n, std::chrono::seconds(1), 4, guard) ==
                  external_provider::Result::revoked &&
              n == 0,
          "post-reply revocation released provider bytes");
  const auto revoked_records = audit_store.query(audit_query);
  require(revoked_records.status.ok() && revoked_records.records.size() == 4 &&
              revoked_records.records[3].outcome ==
                  permissions::AuditOutcome::cancelled,
          "post-reply revocation was not terminally audited");
  std::array<std::byte, external_provider::kMaximumFrameBytes> b{};
  std::array<std::byte, external_provider::kNonceBytes> nonce{};
  nonce[0] = std::byte{1};
  external_provider::RequestFrame canonical{
      r.service_id,
      r.adapter,
      q.authorization,
      definitions::Name(q.operation),
      definitions::CanonicalScope(q.demand_scope),
      payload,
      9,
      nonce};
  require(external_provider::encode_request(canonical, b, n),
          "request encode failed");
  external_provider::RequestFrame decoded{};
  require(external_provider::decode_request(std::span(b).first(n), decoded) &&
              decoded.correlation == 9 &&
              decoded.authorization.binding == binding,
          "request round trip failed");
  require(
      !external_provider::decode_request(std::span(b).first(n - 1), decoded),
      "truncation decoded");
  b[n] = std::byte{};
  require(
      !external_provider::decode_request(std::span(b).first(n + 1), decoded),
      "trailing byte decoded");
  require(external_provider::encode_handshake(r, nonce, b, n) &&
              external_provider::verify_handshake_echo(r, nonce,
                                                       std::span(b).first(n)),
          "handshake failed");
  auto wrong = nonce;
  wrong[1] = std::byte{1};
  require(!external_provider::verify_handshake_echo(r, wrong,
                                                    std::span(b).first(n)),
          "wrong nonce verified");
  const auto registration_document =
      external_provider::canonical_registration_document(r);
  external_provider::Registration parsed;
  require(!registration_document.empty() &&
              external_provider::parse_registration_document(
                  registration_document, getuid(), parsed) ==
                  external_provider::RegistrationLoadResult::loaded &&
              parsed.service_id == r.service_id && parsed.adapter == r.adapter,
          "provider registration document did not round trip");
  std::array registration_template{'/', 't', 'm', 'p', '/', 'o', 'm', 'a', 'r',
                                    'c', 'h', 'y', '-', 'p', 'r', 'o', 'v', '-',
                                    'X', 'X', 'X', 'X', 'X', 'X', '\0'};
  const char *registration_root = mkdtemp(registration_template.data());
  require(registration_root != nullptr, "registration root creation failed");
  const auto registration_path =
      std::filesystem::path(registration_root) / "local.fake-provider.provider";
  {
    std::ofstream output(registration_path);
    output << registration_document;
  }
  chmod(registration_path.c_str(), 0600);
  std::vector<external_provider::Registration> loaded;
  require(external_provider::load_registration_directory(
              registration_root, getuid(), loaded) ==
                  external_provider::RegistrationLoadResult::loaded &&
              loaded.size() == 1,
          "trusted provider registration root did not load");
  require(external_provider::assess_registration_install(loaded, r, {}).decision ==
              external_provider::RegistrationChangeDecision::unchanged,
          "identical provider registration was not unchanged");
  const std::array dependencies{external_provider::ProviderDependency{
      .plugin = permissions::PluginId("org.example.plugin"),
      .revision = digest('b'),
      .adapter = r.adapter}};
  require(external_provider::assess_registration_removal(
              loaded, r.service_id.view(), dependencies)
                  .decision == external_provider::
                                   RegistrationChangeDecision::blocked_by_dependents,
          "provider removal ignored an exact plugin dependency");

  const auto dependency_fixture = std::filesystem::path(DYNAMIC_RADIO_FIXTURE);
  std::ifstream manifest_input(dependency_fixture / "manifest.json");
  const std::string manifest_bytes(
      (std::istreambuf_iterator<char>(manifest_input)), {});
  const auto dependency_manifest = manifest::parse_manifest_v2(manifest_bytes);
  const auto dependency_identity =
      manifest::identify_tree(dependency_fixture, dependency_manifest);
  std::array dependency_template{'/', 't', 'm', 'p', '/', 'o', 'm', 'a', 'r',
                                 'c', 'h', 'y', '-', 'd', 'e', 'p', '-', 'X',
                                 'X', 'X', 'X', 'X', 'X', '\0'};
  const auto *dependency_root = mkdtemp(dependency_template.data());
  require(dependency_root != nullptr, "dependency fixture root failed");
  const auto dependency_base = std::filesystem::path(dependency_root);
  const auto definition_root = dependency_base / "definitions";
  const auto revision_stores = dependency_base / "revisions";
  const auto revision_store = revision_stores / dependency_manifest.id;
  const auto grant_root = dependency_base / "grants";
  const auto index_root = dependency_base / "index";
  std::filesystem::create_directories(definition_root);
  std::filesystem::create_directories(revision_stores);
  std::filesystem::create_directories(index_root);
  chmod(definition_root.c_str(), 0700);
  chmod(revision_stores.c_str(), 0700);
  chmod(index_root.c_str(), 0700);
  const auto definition_path = definition_root / "network-fetch.capability";
  std::filesystem::copy_file(NETWORK_DEFINITION_FIXTURE, definition_path);
  chmod(definition_path.c_str(), 0600);
  definitions::TrustedDefinitionRegistry dependency_registry;
  std::size_t definition_count = 0;
  require(definitions::load_definition_directory(
              definition_root.string(),
              definitions::DefinitionSource::omarchy_package, getuid(),
              {.available = adapter_available}, dependency_registry,
              definition_count) == definitions::LoadResult::loaded &&
              definition_count == 1,
          "dependency definition fixture did not load");
  const auto dynamic_request = definitions::dynamic_request_from_manifest(
      dependency_manifest.requests.front(), dependency_registry);
  require(dynamic_request.has_value(), "dynamic fixture request did not resolve");
  definitions::DynamicRevisionGrant dynamic_grant{
      .binding = {.plugin = permissions::PluginId(dependency_manifest.id),
                  .revision = permissions::Digest(
                      dependency_identity.tree_sha256),
                  .policy_fingerprint = digest('0'),
                  .generation = 1},
      .request = *dynamic_request,
      .grant = {.definition = dynamic_request->definition,
                .operations = {},
                .scope = dynamic_request->scope,
                .state = permissions::GrantState::granted,
                .epoch = 1}};
  for (const auto &operation : dynamic_request->operations.values())
    dynamic_grant.grant.operations.insert(operation);
  require(definitions::review_dynamic_grant(
              dependency_registry, dynamic_grant,
              {.compare = exact_scope}),
          "dynamic dependency fixture was not reviewable");
  permissions::RequestSet no_compiled_requests;
  auto dependency_bundle = grants::make_bundle(
      2, permissions::PluginId(dependency_manifest.id),
      permissions::Digest(dependency_identity.tree_sha256),
      permissions::Digest(dependency_identity.request_sha256), 1,
      no_compiled_requests, {dynamic_grant});
  grants::GrantStore dependency_grants(grant_root);
  const auto staged_grants =
      dependency_grants.stage_candidate(dependency_bundle);
  dependency_grants.activate_candidate(staged_grants.revision.binding);
  store::RevisionStore dependency_revisions(
      revision_store, {.schema_v2_enabled = true});
  require(dependency_revisions
              .stage({.root = dependency_fixture,
                      .manifest = dependency_manifest,
                      .identity = dependency_identity})
              .ok(),
          "dependency revision did not stage");
  require(dependency_revisions
              .activate({.plugin_id = dependency_manifest.id,
                         .revision_sha256 = dependency_identity.tree_sha256,
                         .manifest_sha256 = dependency_identity.manifest_sha256,
                         .source_request_sha256 =
                             dependency_identity.request_sha256,
                         .policy_sha256 = std::string(
                             staged_grants.revision.binding.policy_fingerprint
                                 .view()),
                         .grant_sha256 = grants::revision_grant_fingerprint(
                             staged_grants.revision),
                         .generation = 1})
              .ok(),
          "dependency revision did not activate");
  external_provider::DependencyIndex dependency_index;
  require(external_provider::rebuild_dependency_index(
              dependency_grants, revision_stores, dependency_registry,
              index_root, getuid(), dependency_index) ==
                  external_provider::DependencyIndexResult::rebuilt &&
              dependency_index.dependencies.size() == 1 &&
              dependency_index.dependencies.front().plugin.view() ==
                  dependency_manifest.id,
          "authoritative provider dependency index was not rebuilt");
  const auto indexed_removal = external_provider::assess_registration_removal(
      loaded, r.service_id.view(), dependency_index.dependencies);
  require(indexed_removal.decision ==
              external_provider::RegistrationChangeDecision::installable,
          "unrelated indexed adapter blocked provider removal");
  auto depended_provider = r;
  depended_provider.service_id = definitions::Name("local.radio-provider");
  depended_provider.adapter = dependency_index.dependencies.front().adapter;
  const std::array depended_installed{depended_provider};
  const auto blocked_indexed_removal =
      external_provider::assess_registration_removal(
          depended_installed, depended_provider.service_id.view(),
          dependency_index.dependencies);
  require(blocked_indexed_removal.decision ==
              external_provider::
                  RegistrationChangeDecision::blocked_by_dependents &&
              blocked_indexed_removal.dependents.size() == 1,
          "authoritative indexed dependent did not block provider removal");
  auto replacement = r;
  replacement.executable_digest = digest('f');
  require(external_provider::assess_registration_install(
              loaded, replacement, dependencies)
                  .decision == external_provider::
                                   RegistrationChangeDecision::identity_conflict,
          "invalid replacement was accepted");
  unlink(registration_path.c_str());
  rmdir(registration_root);
  r.executable = "/bin/sh";
  require(!external_provider::valid_registration(r), "shell registered");
  return 0;
}
