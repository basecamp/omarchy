#include "external_provider.hpp"
#include <array>
#include <stdexcept>
#include <string>
#include <unistd.h>
#include <vector>
#include <fstream>

using namespace omarchy::plugins;
namespace {
void require(bool v,std::string_view m){if(!v)throw std::runtime_error(std::string(m));}
definitions::Digest digest(char c){return definitions::Digest(std::string(64,c));}
bool io(int fd,void *p,std::size_t n,bool write_mode){auto *b=static_cast<std::byte*>(p);while(n){auto x=write_mode?write(fd,b,n):read(fd,b,n);if(x<=0)return false;b+=x;n-=x;}return true;}
}
int main(int argc,char **){
 if(argc==2){int fd=3;std::array<std::uint32_t,2> h{};if(!io(fd,h.data(),sizeof(h),false)||h[0]!=1||h[1]>32768)return 70;std::vector<std::byte> p(h[1]);if(!io(fd,p.data(),p.size(),false))return 71;std::uint32_t n=h[1];if(!io(fd,&n,sizeof(n),true)||!io(fd,p.data(),p.size(),true))return 72;return 0;}
 const auto self=std::filesystem::canonical("/proc/self/exe");std::ifstream stream(self,std::ios::binary);const std::string bytes((std::istreambuf_iterator<char>(stream)),{});
 external_provider::Registration r{.service_id=definitions::Name("local.fake-provider"),.adapter={.adapter_class=definitions::Name("fake-bounded-harness"),.implementation_digest=digest('d'),.abi_version=1},.executable=self,.executable_digest=definitions::Digest(manifest::sha256_hex(bytes)),.expected_uid=static_cast<std::uint32_t>(getuid()),.protocol_version=1};
 permissions::ActivationBinding binding{.plugin=permissions::PluginId("org.example.plugin"),.revision=digest('b'),.policy_fingerprint=digest('c'),.generation=2};
 const std::array payload{std::byte{0x2a},std::byte{0x2b}};
 definitions::AuthorizedDynamicRequest q{.authorization={.binding=binding,.definition={.canonical_name=definitions::Name("local.my-harness"),.definition_generation=1,.definition_digest=digest('e')},.grant_epoch=4},.operation="status",.demand_scope="profile=my-harness-v1",.payload=payload};
 std::array<std::byte,16> out{};std::size_t written=0;
 require(external_provider::invoke(r,q,out,written,std::chrono::seconds(1),4)==external_provider::Result::completed&&written==2&&out[0]==payload[0],"bounded external provider E2E failed");
 require(external_provider::invoke(r,q,out,written,std::chrono::seconds(1),5)==external_provider::Result::revoked,"stale grant epoch reached provider");
 r.executable="/bin/sh";require(!external_provider::valid_registration(r),"shell registered as provider");
 return 0;
}
