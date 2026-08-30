#include "dynamic_activation.hpp"

#include <algorithm>
#include <cstring>

namespace omarchy::plugins::definitions {
namespace {
constexpr std::array<std::byte, 8> kGrantMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'D'}, std::byte{'G'},
    std::byte{'R'}, std::byte{'N'}, std::byte{'T'}, std::byte{1}};
constexpr std::array<std::byte, 8> kInvokeMagic{
    std::byte{'O'}, std::byte{'M'}, std::byte{'D'}, std::byte{'I'},
    std::byte{'N'}, std::byte{'V'}, std::byte{'K'}, std::byte{1}};

struct Writer {
  std::span<std::byte> bytes;
  std::size_t offset = 0;
  bool raw(std::span<const std::byte> value) {
    if (value.size() > bytes.size() - std::min(offset, bytes.size())) return false;
    std::copy(value.begin(), value.end(), bytes.begin() + offset);
    offset += value.size(); return true;
  }
  bool u8(std::uint8_t value) { const std::array one{std::byte{value}}; return raw(one); }
  bool u16(std::uint16_t value) {
    const std::array out{std::byte{static_cast<unsigned char>(value >> 8)},
                         std::byte{static_cast<unsigned char>(value)}};
    return raw(out);
  }
  bool u32(std::uint32_t value) {
    std::array<std::byte, 4> out{};
    for (int index = 0; index < 4; ++index)
      out[index] = std::byte{static_cast<unsigned char>(value >> ((3-index)*8))};
    return raw(out);
  }
  bool u64(std::uint64_t value) {
    std::array<std::byte, 8> out{};
    for (int index = 0; index < 8; ++index)
      out[index] = std::byte{static_cast<unsigned char>(value >> ((7-index)*8))};
    return raw(out);
  }
  bool text(std::string_view value) {
    return value.size() <= UINT16_MAX && u16(static_cast<std::uint16_t>(value.size())) &&
           raw(std::as_bytes(std::span(value.data(), value.size())));
  }
};

struct Reader {
  std::span<const std::byte> bytes;
  std::size_t offset = 0;
  bool raw(std::size_t size, std::span<const std::byte> &out) {
    if (size > bytes.size() - std::min(offset, bytes.size())) return false;
    out = bytes.subspan(offset, size); offset += size; return true;
  }
  bool u8(std::uint8_t &value) { std::span<const std::byte> out; if (!raw(1,out)) return false; value=std::to_integer<std::uint8_t>(out[0]); return true; }
  bool u16(std::uint16_t &value) { std::span<const std::byte> out; if(!raw(2,out))return false; value=(std::to_integer<std::uint16_t>(out[0])<<8)|std::to_integer<std::uint16_t>(out[1]); return true; }
  bool u32(std::uint32_t &value) { std::span<const std::byte> out; if(!raw(4,out))return false; value=0; for(auto b:out)value=(value<<8)|std::to_integer<std::uint32_t>(b); return true; }
  bool u64(std::uint64_t &value) { std::span<const std::byte> out; if(!raw(8,out))return false; value=0; for(auto b:out)value=(value<<8)|std::to_integer<std::uint64_t>(b); return true; }
  bool text(std::string_view &value) { std::uint16_t size=0; std::span<const std::byte> out; if(!u16(size)||!raw(size,out)||size==0)return false; value={reinterpret_cast<const char*>(out.data()),out.size()}; return value.find('\0')==std::string_view::npos; }
};

bool write_reference(Writer &writer, const CapabilityReference &reference) {
  return writer.text(reference.canonical_name.view()) &&
         writer.u32(reference.definition_generation) &&
         writer.text(reference.definition_digest.view());
}
bool read_reference(Reader &reader, CapabilityReference &reference) {
  std::string_view name,digest; std::uint32_t generation=0;
  if(!reader.text(name)||!reader.u32(generation)||!reader.text(digest))return false;
  try { reference={.canonical_name=Name(name),.definition_generation=generation,
                   .definition_digest=Digest(digest)}; } catch(...) { return false; }
  return generation>0;
}
} // namespace

bool review_dynamic_grant(const TrustedDefinitionRegistry &registry,
                          const DynamicRevisionGrant &revision,
                          const DynamicScopeValidator &validator) {
  const auto resolved = registry.resolve(revision.request.definition);
  if (!resolved ||
      revision.grant.definition != revision.request.definition ||
      revision.grant.epoch == 0 || validator.compare == nullptr)
    return false;
  if (static_cast<std::uint8_t>(revision.grant.state) >
          static_cast<std::uint8_t>(permissions::GrantState::revoked) ||
      (revision.grant.state == permissions::GrantState::denied
           ? revision.grant.operations != revision.request.operations ||
                 revision.grant.scope != revision.request.scope
           : revision.grant.operations.size() == 0))
    return false;
  if (!std::all_of(revision.request.operations.values().begin(),
                   revision.request.operations.values().end(), [&](const auto &op) {
                     return std::ranges::any_of(
                         resolved->definition->operations.values(),
                         [&](const auto &defined) { return defined.name == op; });
                   })) return false;
  if (!std::all_of(revision.grant.operations.values().begin(),
                   revision.grant.operations.values().end(), [&](const auto &op) {
                     return revision.request.operations.contains(op);
                   })) return false;
  const auto relation=validator.compare(*resolved->definition,
                                        revision.grant.scope.view(),revision.request.scope.view(),validator.context);
  return relation==DynamicScopeRelation::equal ||
         (revision.grant.state != permissions::GrantState::denied &&
          relation==DynamicScopeRelation::narrower);
}

bool encode_dynamic_grant(const DynamicRevisionGrant &revision,
                          std::span<std::byte> output, std::size_t &written) {
  written=0; Writer w{output};
  if(!w.raw(kGrantMagic)||!w.text(revision.binding.plugin.view())||
     !w.text(revision.binding.revision.view())||!w.text(revision.binding.policy_fingerprint.view())||
     !w.u64(revision.binding.generation)||!write_reference(w,revision.request.definition)||
     !w.text(revision.request.scope.view())||!w.u8(revision.request.required?1:0)||
     !w.u8(static_cast<std::uint8_t>(revision.request.operations.size())))return false;
  for(const auto &op:revision.request.operations.values())if(!w.text(op.view()))return false;
  if(!write_reference(w,revision.grant.definition)||!w.text(revision.grant.scope.view())||
     !w.u8(static_cast<std::uint8_t>(revision.grant.state))||!w.u64(revision.grant.epoch)||
     !w.u8(static_cast<std::uint8_t>(revision.grant.operations.size())))return false;
  for(const auto &op:revision.grant.operations.values())if(!w.text(op.view()))return false;
  written=w.offset; return true;
}

bool decode_dynamic_grant(std::span<const std::byte> input,
                          DynamicRevisionGrant &output) {
  output={}; Reader r{input}; std::span<const std::byte> magic;
  std::string_view plugin,revision,policy,scope; std::uint8_t count=0,value=0;
  try {
    if(!r.raw(8,magic)||!std::equal(magic.begin(),magic.end(),kGrantMagic.begin())||
       !r.text(plugin)||!r.text(revision)||!r.text(policy)||!r.u64(output.binding.generation)||
       !read_reference(r,output.request.definition)||!r.text(scope))return false;
    output.binding.plugin=permissions::PluginId(plugin); output.binding.revision=Digest(revision);
    output.binding.policy_fingerprint=Digest(policy); output.request.scope=CanonicalScope(scope);
    if (!r.u8(value) || value > 1 || !r.u8(count) || count > 16)
      return false;
    output.request.required = value == 1;
    for(std::uint8_t i=0;i<count;++i){std::string_view op;if(!r.text(op)||!output.request.operations.insert(Name(op)))return false;}
    if (!read_reference(r, output.grant.definition) || !r.text(scope))
      return false;
    output.grant.scope = CanonicalScope(scope);
    if(!r.u8(value)||value>static_cast<std::uint8_t>(permissions::GrantState::revoked)||!r.u64(output.grant.epoch)||!r.u8(count)||count>16)return false;
    output.grant.state=static_cast<permissions::GrantState>(value);
    for(std::uint8_t i=0;i<count;++i){std::string_view op;if(!r.text(op)||!output.grant.operations.insert(Name(op)))return false;}
  } catch(...) { return false; }
  return r.offset==input.size();
}

bool encode_dynamic_invocation(const DynamicInvocation &invocation,
                               std::span<std::byte> output,std::size_t &written){
  written=0;if(invocation.payload.size()>kMaximumDynamicPayloadBytes)return false;Writer w{output};
  if(!w.raw(kInvokeMagic)||!write_reference(w,invocation.definition)||!w.text(invocation.operation.view())||
     !w.text(invocation.demand_scope.view())||!w.u8(invocation.gesture ? 1 : 0))return false;
  if(invocation.gesture&&(!w.u64(invocation.gesture->surface_id)||
     !w.u64(invocation.gesture->surface_generation)||
     !w.u64(invocation.gesture->input_sequence)))return false;
  if(!w.u32(static_cast<std::uint32_t>(invocation.payload.size()))||!w.raw(invocation.payload))return false;
  written=w.offset;return true;
}
bool decode_dynamic_invocation(std::span<const std::byte> input,DynamicInvocation &output){
  output={};if(input.size()>kMaximumDynamicEnvelopeBytes)return false;Reader r{input};std::span<const std::byte> magic,payload;std::string_view op,scope;std::uint32_t size=0;std::uint8_t gesture=0;
  try{if(!r.raw(8,magic)||!std::equal(magic.begin(),magic.end(),kInvokeMagic.begin())||!read_reference(r,output.definition)||!r.text(op)||!r.text(scope)||!r.u8(gesture)||gesture>1)return false;
  if(gesture){DynamicInvocation::GestureClaim claim;if(!r.u64(claim.surface_id)||!r.u64(claim.surface_generation)||!r.u64(claim.input_sequence)||claim.surface_id==0||claim.surface_generation==0||claim.input_sequence==0)return false;output.gesture=claim;}
  if(!r.u32(size)||size>kMaximumDynamicPayloadBytes||!r.raw(size,payload)||r.offset!=input.size())return false;
  output.operation=Name(op);output.demand_scope=CanonicalScope(scope);output.payload=payload;}catch(...){return false;}return true;
}

DynamicDispatchResult dispatch_dynamic_invocation(const TrustedDefinitionRegistry &registry,
 const DynamicRevisionGrant &revision,const permissions::ActivationBinding &channel_binding,
 std::span<const std::byte> envelope,const DynamicAdapter &adapter,const DynamicScopeValidator &validator,
 bool fresh_gesture,std::span<std::byte> response,std::size_t &written,DynamicDecision &decision){
  written=0;decision=DynamicDecision::denied;if(channel_binding!=revision.binding)return DynamicDispatchResult::stale_activation;
  DynamicInvocation invocation;if(!decode_dynamic_invocation(envelope,invocation))return DynamicDispatchResult::malformed;
  if(invocation.definition!=revision.request.definition)return DynamicDispatchResult::denied;
  const auto auth=authorize_dynamic_operation(registry,revision.request,revision.grant,invocation.operation.view(),invocation.demand_scope.view(),adapter.binding,validator,fresh_gesture);decision=auth.decision;
  if(!auth.allowed()||adapter.dispatch==nullptr)return DynamicDispatchResult::denied;
  const AuthorizedDynamicRequest request{
      .authorization = {.binding = channel_binding,
                        .definition = revision.grant.definition,
                        .grant_epoch = revision.grant.epoch},
      .operation = invocation.operation.view(),
      .demand_scope = invocation.demand_scope.view(),
      .payload = invocation.payload};
  if(!adapter.dispatch(request,response,written,adapter.context)||written>response.size())return DynamicDispatchResult::adapter_failed;
  return DynamicDispatchResult::dispatched;
}
} // namespace omarchy::plugins::definitions
