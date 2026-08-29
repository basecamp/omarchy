#include "external_provider.hpp"
#include <array>
#include <cerrno>
#include <cstring>
#include <poll.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

namespace omarchy::plugins::external_provider {
namespace {
bool all(int fd, const void *data, std::size_t size) { const auto *p=static_cast<const std::byte*>(data); while(size){auto n=write(fd,p,size);if(n<=0)return false;p+=n;size-=n;}return true; }
bool read_all(int fd, void *data, std::size_t size) { auto *p=static_cast<std::byte*>(data); while(size){auto n=read(fd,p,size);if(n<=0)return false;p+=n;size-=n;}return true; }
}
bool valid_registration(const Registration &v) {
  if(v.service_id.view().empty() || v.adapter.abi_version == 0 ||
     v.protocol_version != 1 || !v.executable.is_absolute() ||
     v.executable.filename() == "sh" || v.executable.filename() == "bash" ||
     v.executable_digest.size() != 64) return false;
  const int fd=open(v.executable.c_str(),O_RDONLY|O_CLOEXEC|O_NOFOLLOW);struct stat s{};
  if(fd<0||fstat(fd,&s)!=0||!S_ISREG(s.st_mode)||static_cast<std::uint32_t>(s.st_uid)!=v.expected_uid||(s.st_mode&(S_IWGRP|S_IWOTH))||s.st_size<=0||s.st_size>64*1024*1024){if(fd>=0)close(fd);return false;}
  std::string bytes(static_cast<std::size_t>(s.st_size),'\0');const auto n=read(fd,bytes.data(),bytes.size());close(fd);
  return n==s.st_size&&definitions::Digest(manifest::sha256_hex(bytes))==v.executable_digest;
}
Result invoke(const Registration &r,const definitions::AuthorizedDynamicRequest &q,
              std::span<std::byte> out,std::size_t &written,
              std::chrono::milliseconds timeout,std::uint64_t epoch) {
  written=0;if(!valid_registration(r))return Result::invalid_registration;
  if(epoch==0||epoch!=q.authorization.grant_epoch)return Result::revoked;
  if(q.payload.size()>definitions::kMaximumDynamicPayloadBytes||out.size()>definitions::kMaximumDynamicPayloadBytes)return Result::malformed;
  int fd[2];if(socketpair(AF_UNIX,SOCK_SEQPACKET|SOCK_CLOEXEC,0,fd)!=0)return Result::crashed;
  const auto pid=fork();if(pid<0){close(fd[0]);close(fd[1]);return Result::crashed;}
  if(pid==0){close(fd[0]);dup2(fd[1],3);close(fd[1]);execl(r.executable.c_str(),r.executable.c_str(),"--omarchy-provider-fd=3",nullptr);_exit(127);}
  close(fd[1]);std::array<std::uint32_t,2> header{1,static_cast<std::uint32_t>(q.payload.size())};
  if(!all(fd[0],header.data(),sizeof(header))||!all(fd[0],q.payload.data(),q.payload.size())){close(fd[0]);waitpid(pid,nullptr,0);return Result::crashed;}
  pollfd p{fd[0],POLLIN,0};if(poll(&p,1,static_cast<int>(timeout.count()))<=0){kill(pid,SIGKILL);close(fd[0]);waitpid(pid,nullptr,0);return Result::timeout;}
  std::uint32_t size=0;if(!read_all(fd[0],&size,sizeof(size))||size>out.size()||!read_all(fd[0],out.data(),size)){close(fd[0]);waitpid(pid,nullptr,0);return Result::malformed;}
  written=size;close(fd[0]);int status=0;waitpid(pid,&status,0);return WIFEXITED(status)&&WEXITSTATUS(status)==0?Result::completed:Result::crashed;
}
} // namespace omarchy::plugins::external_provider
