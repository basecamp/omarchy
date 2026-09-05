#include "capability_definition_loader.hpp"

#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <span>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {
using namespace omarchy::plugins::definitions;

struct OperationSpec {
  std::string_view name;
  std::string_view label;
  bool mutating = false;
  bool gesture = false;
};

struct CatalogSpec {
  std::string_view name;
  std::string_view authority;
  EnforcementFamily family;
  std::string_view category_id;
  std::string_view category_label;
  ScopeSchema scope;
  std::string_view title;
  std::string_view risk_text;
  RiskLevel risk;
  RevocationPolicy revocation;
  std::string_view adapter_class;
  std::string_view contract;
  std::span<const OperationSpec> operations;
};

constexpr std::array network_operations{
    OperationSpec{"fetch", "Fetch bounded data"}};
constexpr std::array open_operations{
    OperationSpec{"open", "Open a link", true, true}};
constexpr std::array observe_operations{
    OperationSpec{"observe", "Observe selected data"}};
constexpr std::array control_operations{
    OperationSpec{"control", "Change selected controls", true, true}};
constexpr std::array read_operations{
    OperationSpec{"read", "Read selected account data"}};
constexpr std::array write_operations{
    OperationSpec{"write", "Change selected account data", true, true}};
constexpr std::array media_operations{
    OperationSpec{"play", "Play an approved source", true},
    OperationSpec{"control", "Control approved playback", true}};
constexpr std::array execute_operations{
    OperationSpec{"run", "Run an approved command", true}};

constexpr std::array catalog{
    CatalogSpec{
        "network.fetch", "network.fetch-v1", EnforcementFamily::network_fetch,
        "network.access", "Network access",
        ScopeSchema::https_origins_and_methods,
        "Fetch from selected HTTPS origins",
        "Sends bounded requests only to the selected origins and methods",
        RiskLevel::high, RevocationPolicy::cancel_inflight,
        "bounded-network-fetch",
        "bounded-network-fetch-v1;request=method,origin,path,headers,body,"
        "response-type,media-json-pointers;response=status,content-type,"
        "body-or-json,source-handles;"
        "scope=https-origins-methods;redirects=reject;"
        "resolved-addresses=public-only;limits=provider-fixed",
        network_operations},
    CatalogSpec{"external.open-uri.https", "external.open-uri.https-v1",
                EnforcementFamily::external_open_uri, "desktop.actions",
                "Desktop actions", ScopeSchema::https_origins_after_gesture,
                "Open selected HTTPS sites",
                "Opens a user-visible HTTPS address after one fresh gesture",
                RiskLevel::moderate, RevocationPolicy::deny_new,
                "desktop-open-uri",
                "desktop-open-uri-v1;request=url,presentation;response=result;"
                "scope=https-origins-gesture;gesture=fresh;scheme=https;"
                "origin=revalidated-by-provider;launch=trusted-desktop",
                open_operations},
    CatalogSpec{
        "system.observe", "system.observe-v1",
        EnforcementFamily::system_observe, "system.observation",
        "System observation", ScopeSchema::named_sanitized_datasets,
        "Observe selected system data",
        "Reads only selected bounded datasets after provider sanitization",
        RiskLevel::moderate, RevocationPolicy::cancel_inflight,
        "sanitized-system-observe",
        "sanitized-system-observe-v1;request=dataset;response=bounded-records;"
        "scope=named-sanitized-datasets;identifiers=opaque;"
        "raw-system-metadata=forbidden",
        observe_operations},
    CatalogSpec{
        "device.observe", "device.observe-v1",
        EnforcementFamily::device_observe, "hardware.devices",
        "Hardware devices", ScopeSchema::selected_device_fields,
        "Observe a selected device",
        "Reads only the selected fields from one explicitly selected device",
        RiskLevel::moderate, RevocationPolicy::cancel_inflight,
        "selected-device-observe",
        "selected-device-observe-v1;request=status;response=selected-fields;"
        "scope=selected-device-fields;device=provider-bound;"
        "hardware-identifiers=redacted",
        observe_operations},
    CatalogSpec{
        "device.control", "device.control-v1",
        EnforcementFamily::device_control, "hardware.devices",
        "Hardware devices", ScopeSchema::selected_device_controls,
        "Control a selected device",
        "Changes only selected controls on one explicitly selected device",
        RiskLevel::high, RevocationPolicy::cancel_inflight,
        "selected-device-control",
        "selected-device-control-v1;request=control,value;response=result;"
        "scope=selected-device-controls;device=provider-bound;"
        "gesture=fresh",
        control_operations},
    CatalogSpec{
        "remote-account.read", "remote-account.read-v1",
        EnforcementFamily::remote_account_read, "online.accounts",
        "Online accounts", ScopeSchema::selected_remote_account,
        "Read selected remote account data",
        "Reads only selected datasets from one explicitly selected account",
        RiskLevel::high, RevocationPolicy::cancel_inflight,
        "remote-account-read",
        "remote-account-read-v1;request=dataset,query;response=bounded-records;"
        "scope=selected-remote-account;credentials=provider-only;"
        "identifiers=opaque",
        read_operations},
    CatalogSpec{
        "remote-account.write", "remote-account.write-v1",
        EnforcementFamily::remote_account_write, "online.accounts",
        "Online accounts", ScopeSchema::selected_remote_account,
        "Change selected remote account data",
        "Changes only selected actions on one explicitly selected account",
        RiskLevel::critical, RevocationPolicy::cancel_inflight,
        "remote-account-write",
        "remote-account-write-v1;request=action,opaque-resource-handle;"
        "response=result;scope=selected-remote-account;"
        "credentials=provider-only;gesture=fresh",
        write_operations},
    CatalogSpec{
        "media.play-stream", "media.play-stream-v1",
        EnforcementFamily::media_play_stream, "media.playback",
        "Media playback", ScopeSchema::activation_source_handles_and_controls,
        "Play approved media sources",
        "Plays and controls only sources approved during this activation",
        RiskLevel::moderate, RevocationPolicy::cancel_inflight,
        "activation-media-stream",
        "activation-media-stream-v1;request=source-handle,control,value;"
        "response=playback-state;scope=activation-source-handles-controls;"
        "source=provider-bound;teardown=revocation",
        media_operations},
    CatalogSpec{
        "bash.execute", "bash.execute-v1", EnforcementFamily::cli_harness,
        "local.automation", "Local automation", ScopeSchema::exact_cli_profile,
        "Run selected command-line tools",
        "Runs only commands and arguments accepted by an installed trusted profile",
        RiskLevel::critical, RevocationPolicy::cancel_inflight,
        "bounded-command-execute",
        "bounded-command-execute-v1;request=command,arguments;"
        "response=exit-code,stdout,stderr;scope=exact-cli-profile;"
        "shell-parsing=forbidden;environment=provider-fixed;"
        "executable=provider-pinned;limits=provider-profile",
        execute_operations},
};

CapabilityDefinition make_definition(const CatalogSpec &spec) {
  CapabilityDefinition definition{
      .canonical_name = Name(spec.name),
      .authority_identity = Name(spec.authority),
      .enforcement_family = spec.family,
      .display_category_id = Name(spec.category_id),
      .display_category_label = Label(spec.category_label),
      .scope_schema = spec.scope,
      .title = Label(spec.title),
      .risk_text = Label(spec.risk_text),
      .risk = spec.risk,
      .revocation = spec.revocation,
      .audit = {},
      .adapter = {.adapter_class = Name(spec.adapter_class),
                  .contract_digest = semantic_contract_digest(spec.contract),
                  .abi_version = 1},
      .operations = {},
  };
  for (const auto &operation : spec.operations) {
    if (!definition.operations.insert(
            {.name = Name(operation.name),
             .label = Label(operation.label),
             .mutating = operation.mutating,
             .requires_fresh_gesture = operation.gesture}))
      throw std::runtime_error("duplicate catalog operation");
  }
  if (!valid_definition(definition))
    throw std::runtime_error("invalid built-in definition: " +
                             std::string(spec.name));
  return definition;
}

void write_file(const std::filesystem::path &path, std::string_view contents) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output.exceptions(std::ios::badbit | std::ios::failbit);
  output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
}

std::string json_string(std::string_view value) {
  std::string output;
  output.reserve(value.size() + 2);
  output.push_back('"');
  for (const char byte : value) {
    if (byte == '"' || byte == '\\')
      output.push_back('\\');
    output.push_back(byte);
  }
  output.push_back('"');
  return output;
}

} // namespace

int main(int argc, char **argv) {
  try {
    if (argc != 2)
      throw std::runtime_error(
          "usage: generate-builtin-catalog OUTPUT-DIRECTORY");
    const std::filesystem::path output_root(argv[1]);
    const auto definitions_root = output_root / "capabilities.d";
    std::filesystem::create_directories(definitions_root);

    std::string index = "{\n  \"schemaVersion\": 1,\n  \"definitions\": [\n";
    for (std::size_t position = 0; position < catalog.size(); ++position) {
      const auto &spec = catalog[position];
      const auto definition = make_definition(spec);
      const auto document = canonical_definition_document(definition, 1);
      if (document.empty())
        throw std::runtime_error("definition document exceeded its contract");
      write_file(definitions_root / (std::string(spec.name) + ".capability"),
                 document);
      index += "    {\"capability\":" + json_string(spec.name) +
               ",\"definitionGeneration\":1,\"definitionDigest\":" +
               json_string(definition_digest(definition).view()) +
               ",\"contractDigest\":" +
               json_string(definition.adapter.contract_digest.view()) + "}";
      index += position + 1 == catalog.size() ? "\n" : ",\n";
    }
    index += "  ],\n  \"manifestReferencesRequireExactPins\": true\n}\n";
    write_file(output_root / "capability-catalog-v1.json", index);
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "catalog generation failed: " << error.what() << '\n';
    return 1;
  }
}
