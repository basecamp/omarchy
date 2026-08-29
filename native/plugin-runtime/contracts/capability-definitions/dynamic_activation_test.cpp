#include "dynamic_activation.hpp"

#include <array>
#include <stdexcept>
#include <string>

namespace {
using namespace omarchy::plugins::definitions;
namespace permissions = omarchy::plugins::permissions;
void require(bool value,std::string_view message){if(!value)throw std::runtime_error(std::string(message));}
Digest digest(char value){return Digest(std::string(64,value));}
DynamicScopeRelation scope_compare(const CapabilityDefinition &,
                                   std::string_view candidate,
                                   std::string_view baseline, void *) noexcept {
  if (candidate == baseline)
    return DynamicScopeRelation::equal;
  if (candidate == "narrow" && baseline == "wide")
    return DynamicScopeRelation::narrower;
  if (candidate == "wide" && baseline == "narrow")
    return DynamicScopeRelation::expanded;
  return DynamicScopeRelation::incomparable;
}
bool adapter_dispatch(std::string_view operation,std::string_view scope,std::span<const std::byte> payload,std::span<std::byte> response,std::size_t &written,void *context) noexcept {
 auto &calls=*static_cast<int*>(context);if(operation!="read"||scope!="narrow"||payload.size()!=1||response.empty())return false;++calls;response[0]=payload[0];written=1;return true;}
CapabilityDefinition definition(){CapabilityDefinition d{.canonical_name=Name("local.status"),.authority_identity=Name("local.status-v1"),.enforcement_family=EnforcementFamily::network_fetch,.display_category_id=Name("local.services"),.display_category_label=Label("Local services"),.scope_schema=ScopeSchema::https_origins_and_methods,.title=Label("Read selected status"),.risk_text=Label("Sends a bounded request to a selected service"),.risk=RiskLevel::moderate,.revocation=RevocationPolicy::cancel_inflight,.audit={},.adapter={.adapter_class=Name("status-adapter"),.implementation_digest=digest('a'),.abi_version=1},.operations={}};d.operations.insert({.name=Name("read"),.label=Label("Read status")});return d;}
permissions::ActivationBinding binding(std::uint64_t generation=5){return {.plugin=permissions::PluginId("org.example.dynamic"),.revision=digest('b'),.policy_fingerprint=digest('c'),.generation=generation};}
}

void dynamic_activation_tests(){
 TrustedDefinitionRegistry registry;auto def=definition();require(registry.install(def,DefinitionSource::local_admin,3),"definition install failed");auto resolved=registry.find("local.status");require(resolved.has_value(),"definition missing");
 DynamicRevisionGrant revision{.binding=binding(),.request={.definition={.canonical_name=Name("local.status"),.definition_generation=3,.definition_digest=resolved->digest},.operations={},.scope=CanonicalScope("wide"),.required=true},.grant={.definition={.canonical_name=Name("local.status"),.definition_generation=3,.definition_digest=resolved->digest},.operations={},.scope=CanonicalScope("narrow"),.state=permissions::GrantState::granted,.epoch=8}};
 revision.request.operations.insert(Name("read"));revision.grant.operations.insert(Name("read"));DynamicScopeValidator validator{.compare=scope_compare};require(review_dynamic_grant(registry,revision,validator),"review rejected narrowed grant");
 std::array<std::byte,16384> persisted{};std::size_t persisted_size=0;require(encode_dynamic_grant(revision,persisted,persisted_size),"grant persistence encode failed");DynamicRevisionGrant restored;require(decode_dynamic_grant(std::span(persisted).first(persisted_size),restored)&&review_dynamic_grant(registry,restored,validator),"persisted grant did not review");
 const std::array payload{std::byte{0x2a}};DynamicInvocation invocation{.definition=revision.request.definition,.operation=Name("read"),.demand_scope=CanonicalScope("narrow"),.payload=payload};std::array<std::byte,kMaximumDynamicEnvelopeBytes> envelope{};std::size_t envelope_size=0;require(encode_dynamic_invocation(invocation,envelope,envelope_size),"invoke encode failed");const auto valid_envelope_size=envelope_size;
 int calls=0;DynamicAdapter adapter{.binding=def.adapter,.dispatch=adapter_dispatch,.context=&calls};std::array<std::byte,8> response{};std::size_t written=0;DynamicDecision decision{};auto run=[&](const DynamicRevisionGrant&r,const permissions::ActivationBinding&b,const DynamicAdapter&a,std::span<const std::byte> bytes){return dispatch_dynamic_invocation(registry,r,b,bytes,a,validator,false,response,written,decision);};
 require(run(restored,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::dispatched&&calls==1&&written==1,"end-to-end dynamic dispatch failed");
 auto mutated=envelope;mutated[12]^=std::byte{1};require(run(restored,binding(),adapter,std::span(mutated).first(envelope_size))!=DynamicDispatchResult::dispatched&&calls==1,"spoofed definition name dispatched");
 auto wrong_digest=invocation;wrong_digest.definition.definition_digest=digest('f');require(encode_dynamic_invocation(wrong_digest,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"spoofed definition digest dispatched");
 auto wrong_generation=invocation;wrong_generation.definition.definition_generation=4;require(encode_dynamic_invocation(wrong_generation,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"spoofed definition generation dispatched");
 auto wrong_adapter=adapter;wrong_adapter.binding.implementation_digest=digest('e');require(run(restored,binding(),wrong_adapter,std::span(envelope).first(envelope_size))==DynamicDispatchResult::denied,"spoofed adapter dispatched");
 auto undeclared=invocation;undeclared.operation=Name("write");require(encode_dynamic_invocation(undeclared,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"undeclared operation dispatched");
 auto expanded=invocation;expanded.demand_scope=CanonicalScope("wide");require(encode_dynamic_invocation(expanded,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied&&decision==DynamicDecision::scope_expanded,"expanded scope dispatched");
 auto denied=restored;denied.grant.state=permissions::GrantState::denied;require(run(denied,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::denied,"denied grant dispatched");auto revoked=restored;revoked.grant.state=permissions::GrantState::revoked;require(run(revoked,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::denied,"revoked grant dispatched");
 require(run(restored,binding(6),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::stale_activation,"stale plugin generation dispatched");auto stale_revision=binding();stale_revision.revision=digest('d');require(run(restored,stale_revision,adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::stale_activation,"stale plugin revision dispatched");
 TrustedDefinitionRegistry empty;require(dispatch_dynamic_invocation(empty,restored,binding(),std::span(envelope).first(valid_envelope_size),adapter,validator,false,response,written,decision)==DynamicDispatchResult::denied&&decision==DynamicDecision::unknown_definition,"unknown definition dispatched");
 auto broader=restored;broader.grant.scope=CanonicalScope("wide");broader.request.scope=CanonicalScope("narrow");require(!review_dynamic_grant(registry,broader,validator),"expanded persisted grant passed review");
}
