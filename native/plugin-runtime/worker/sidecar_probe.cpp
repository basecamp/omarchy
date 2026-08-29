#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <fstream>
#include <string>

namespace {

bool descriptor_closed(int descriptor) {
  errno = 0;
  return fcntl(descriptor, F_GETFD) < 0 && errno == EBADF;
}

} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  const bool descriptors_closed = descriptor_closed(3) &&
                                  descriptor_closed(4) &&
                                  descriptor_closed(5);
  const std::string temporary = std::string(argv[1]) + ".tmp";
  std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
  output << getpid() << ' ' << (descriptors_closed ? "closed" : "open")
         << '\n';
  output.close();
  if (!output || rename(temporary.c_str(), argv[1]) < 0)
    return 3;
  for (;;)
    pause();
}
