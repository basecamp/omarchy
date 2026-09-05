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
bool adapter_dispatch(const AuthorizedDynamicRequest &request,std::span<std::byte> response,std::size_t &written,void *context) noexcept {
 auto &calls=*static_cast<int*>(context);if((request.operation!="read"&&request.operation!="write")||request.demand_scope!="narrow"||request.payload.size()!=1||response.empty()||request.authorization.binding.plugin.view()!="org.example.dynamic"||request.authorization.binding.generation!=5||request.authorization.definition.canonical_name.view()!="local.status"||request.authorization.grant_epoch!=8)return false;++calls;response[0]=request.payload[0];written=1;return true;}
CapabilityDefinition definition(){CapabilityDefinition d{.canonical_name=Name("local.status"),.authority_identity=Name("local.status-v1"),.enforcement_family=EnforcementFamily::network_fetch,.display_category_id=Name("local.services"),.display_category_label=Label("Local services"),.scope_schema=ScopeSchema::https_origins_and_methods,.title=Label("Read selected status"),.risk_text=Label("Sends a bounded request to a selected service"),.risk=RiskLevel::moderate,.revocation=RevocationPolicy::cancel_inflight,.audit={},.adapter={.adapter_class=Name("status-adapter"),.contract_digest=digest('a'),.abi_version=1},.operations={}};d.operations.insert({.name=Name("read"),.label=Label("Read status")});d.operations.insert({.name=Name("write"),.label=Label("Change status"),.mutating=true,.requires_fresh_gesture=true});return d;}
permissions::ActivationBinding binding(std::uint64_t generation=5){return {.plugin=permissions::PluginId("org.example.dynamic"),.revision=digest('b'),.policy_fingerprint=digest('c'),.generation=generation};}
}

void dynamic_activation_tests(){
 TrustedDefinitionRegistry registry;auto def=definition();require(registry.install(def,DefinitionSource::local_admin,3),"definition install failed");auto resolved=registry.find("local.status");require(resolved.has_value(),"definition missing");
 DynamicRevisionGrant revision{.binding=binding(),.request={.definition={.canonical_name=Name("local.status"),.definition_generation=3,.definition_digest=resolved->digest},.operations={},.scope=CanonicalScope("wide"),.required=true},.grant={.definition={.canonical_name=Name("local.status"),.definition_generation=3,.definition_digest=resolved->digest},.operations={},.scope=CanonicalScope("narrow"),.state=permissions::GrantState::granted,.epoch=8}};
 revision.request.operations.insert(Name("read"));revision.grant.operations.insert(Name("read"));DynamicScopeValidator validator{.compare=scope_compare};require(review_dynamic_grant(registry,revision,validator),"review rejected narrowed grant");
 std::array<std::byte,16384> persisted{};std::size_t persisted_size=0;require(encode_dynamic_grant(revision,persisted,persisted_size),"grant persistence encode failed");DynamicRevisionGrant restored;require(decode_dynamic_grant(std::span(persisted).first(persisted_size),restored)&&review_dynamic_grant(registry,restored,validator),"persisted grant did not review");
 require(restored.binding==revision.binding&&restored.request==revision.request&&restored.grant.definition==revision.grant.definition&&restored.grant.scope==revision.grant.scope&&restored.grant.operations==revision.grant.operations&&restored.grant.epoch==8,"persisted dynamic grant did not reconstruct exactly");
 auto undefined_operation=restored;undefined_operation.request.operations.insert(Name("admin"));undefined_operation.grant.operations.insert(Name("admin"));require(!review_dynamic_grant(registry,undefined_operation,validator),"persisted undefined operation passed review");
 auto noncanonical_scope=restored;noncanonical_scope.grant.scope=CanonicalScope(" narrow");require(!review_dynamic_grant(registry,noncanonical_scope,validator),"non-canonical persisted scope passed review");
 auto stale_definition=restored;stale_definition.request.definition.definition_generation=4;stale_definition.grant.definition.definition_generation=4;require(!review_dynamic_grant(registry,stale_definition,validator),"stale persisted definition generation passed review");
 auto zero_epoch=restored;zero_epoch.grant.epoch=0;require(!review_dynamic_grant(registry,zero_epoch,validator),"zero persisted grant epoch passed review");
 auto empty_granted=restored;empty_granted.grant.operations={};require(!review_dynamic_grant(registry,empty_granted,validator),"empty granted operation set passed review");
 auto empty_revoked=restored;empty_revoked.grant.state=permissions::GrantState::revoked;empty_revoked.grant.operations={};require(!review_dynamic_grant(registry,empty_revoked,validator),"empty revoked operation set passed review");
 auto denied_exact=restored;denied_exact.grant.state=permissions::GrantState::denied;denied_exact.grant.scope=denied_exact.request.scope;require(review_dynamic_grant(registry,denied_exact,validator),"exact denied operation set failed review");
 auto denied_empty=denied_exact;denied_empty.grant.operations={};require(!review_dynamic_grant(registry,denied_empty,validator),"denied persisted grant dropped requested operations");
 auto denied_narrowed=denied_exact;denied_narrowed.request.scope=CanonicalScope("wide");denied_narrowed.grant.scope=CanonicalScope("narrow");require(!review_dynamic_grant(registry,denied_narrowed,validator),"denied persisted grant narrowed its request scope");
 auto partial_required=restored;partial_required.request.operations.insert(Name("write"));require(review_dynamic_grant(registry,partial_required,validator),"nonempty partial required grant failed review");
 auto partial_revoked=partial_required;partial_revoked.grant.state=permissions::GrantState::revoked;require(review_dynamic_grant(registry,partial_revoked,validator),"revocation lost a nonempty partial operation set");
 auto malformed_state=restored;malformed_state.grant.state=static_cast<permissions::GrantState>(99);require(!review_dynamic_grant(registry,malformed_state,validator),"malformed dynamic grant state passed review");
 auto unsupported_version_record=persisted;unsupported_version_record[7]=std::byte{0};DynamicRevisionGrant rejected;require(!decode_dynamic_grant(std::span(unsupported_version_record).first(persisted_size),rejected),"unsupported dynamic grant record version decoded");
 require(!decode_dynamic_grant(std::span(persisted).first(persisted_size-1),rejected),"truncated dynamic grant record decoded");
 persisted[persisted_size]=std::byte{0};require(!decode_dynamic_grant(std::span(persisted).first(persisted_size+1),rejected),"dynamic grant record with trailing data decoded");
 const std::array payload{std::byte{0x2a}};DynamicInvocation invocation{.definition=revision.request.definition,.operation=Name("read"),.demand_scope=CanonicalScope("narrow"),.gesture={},.payload=payload};std::array<std::byte,kMaximumDynamicEnvelopeBytes> envelope{};std::size_t envelope_size=0;require(encode_dynamic_invocation(invocation,envelope,envelope_size),"invoke encode failed");const auto valid_envelope_size=envelope_size;
 int calls=0;DynamicAdapter adapter{.binding=def.adapter,.dispatch=adapter_dispatch,.context=&calls};std::array<std::byte,8> response{};std::size_t written=0;DynamicDecision decision{};auto run=[&](const DynamicRevisionGrant&r,const permissions::ActivationBinding&b,const DynamicAdapter&a,std::span<const std::byte> bytes){return dispatch_dynamic_invocation(registry,r,b,bytes,a,validator,false,response,written,decision);};
 require(run(restored,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::dispatched&&calls==1&&written==1,"end-to-end dynamic dispatch failed");
 auto missing_adapter=adapter;missing_adapter.dispatch=nullptr;require(run(restored,binding(),missing_adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::denied&&calls==1,"missing adapter dispatched");
 auto mutated=envelope;mutated[12]^=std::byte{1};require(run(restored,binding(),adapter,std::span(mutated).first(envelope_size))!=DynamicDispatchResult::dispatched&&calls==1,"spoofed definition name dispatched");
 auto wrong_digest=invocation;wrong_digest.definition.definition_digest=digest('f');require(encode_dynamic_invocation(wrong_digest,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"spoofed definition digest dispatched");
 auto wrong_generation=invocation;wrong_generation.definition.definition_generation=4;require(encode_dynamic_invocation(wrong_generation,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"spoofed definition generation dispatched");
 auto wrong_adapter=adapter;wrong_adapter.binding.contract_digest=digest('e');require(run(restored,binding(),wrong_adapter,std::span(envelope).first(envelope_size))==DynamicDispatchResult::denied,"spoofed adapter dispatched");
 auto undeclared=invocation;undeclared.operation=Name("write");require(encode_dynamic_invocation(undeclared,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied,"undeclared operation dispatched");
 auto gesture_revision=restored;gesture_revision.request.operations.insert(Name("write"));gesture_revision.grant.operations.insert(Name("write"));require(run(gesture_revision,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied&&calls==1,"mutation without fresh gesture dispatched");require(dispatch_dynamic_invocation(registry,gesture_revision,binding(),std::span(mutated).first(envelope_size),adapter,validator,true,response,written,decision)==DynamicDispatchResult::dispatched&&calls==2,"fresh gesture did not authorize declared mutation");
 auto expanded=invocation;expanded.demand_scope=CanonicalScope("wide");require(encode_dynamic_invocation(expanded,mutated,envelope_size)&&run(restored,binding(),adapter,std::span(mutated).first(envelope_size))==DynamicDispatchResult::denied&&decision==DynamicDecision::scope_expanded,"expanded scope dispatched");
 auto denied=restored;denied.grant.state=permissions::GrantState::denied;require(run(denied,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::denied,"denied grant dispatched");auto revoked=restored;revoked.grant.state=permissions::GrantState::revoked;require(run(revoked,binding(),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::denied,"revoked grant dispatched");
 require(run(restored,binding(6),adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::stale_activation,"stale plugin generation dispatched");auto stale_revision=binding();stale_revision.revision=digest('d');require(run(restored,stale_revision,adapter,std::span(envelope).first(valid_envelope_size))==DynamicDispatchResult::stale_activation,"stale plugin revision dispatched");
 TrustedDefinitionRegistry empty;require(dispatch_dynamic_invocation(empty,restored,binding(),std::span(envelope).first(valid_envelope_size),adapter,validator,false,response,written,decision)==DynamicDispatchResult::denied&&decision==DynamicDecision::unknown_definition,"unknown definition dispatched");
 auto broader=restored;broader.grant.scope=CanonicalScope("wide");broader.request.scope=CanonicalScope("narrow");require(!review_dynamic_grant(registry,broader,validator),"expanded persisted grant passed review");

 DynamicPendingTable<2> pending;
 require(pending.begin(71, restored.binding, restored.grant.definition,
                       restored.grant.epoch) ==
             DynamicPendingDecision::accepted,
         "dynamic pending operation was not tracked");
 require(pending.begin(71, restored.binding, restored.grant.definition,
                       restored.grant.epoch) ==
             DynamicPendingDecision::duplicate,
         "dynamic correlation replay was accepted");
 std::array<std::uint64_t, 2> cancelled{};
 require(pending.revoke(restored.grant.definition, restored.grant.epoch,
                        cancelled) == 1 &&
             cancelled[0] == 71,
         "dynamic revocation did not select pending work for cancellation");
 require(pending.complete(71, restored.binding, restored.grant.definition,
                          restored.grant.epoch) ==
             DynamicPendingDecision::cancelled,
         "revoked dynamic work completed under its old epoch");

 require(pending.begin(72, restored.binding, restored.grant.definition,
                       restored.grant.epoch) ==
             DynamicPendingDecision::accepted,
         "dynamic update fixture was not tracked");
 auto next_binding = restored.binding;
 ++next_binding.generation;
 cancelled = {};
 require(pending.invalidate_activation(next_binding, cancelled) == 1 &&
             cancelled[0] == 72,
         "activation update did not cancel stale dynamic work");
 require(pending.complete(72, next_binding, restored.grant.definition,
                          restored.grant.epoch + 1) ==
             DynamicPendingDecision::stale_activation,
         "pending dynamic work crossed an activation update");
}
