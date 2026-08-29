#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <cerrno>
#include <fstream>
#include <string>

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  const bool descriptors_closed =
      fcntl(3, F_GETFD) < 0 && errno == EBADF && fcntl(4, F_GETFD) < 0 &&
      errno == EBADF && fcntl(5, F_GETFD) < 0 && errno == EBADF;
  std::ofstream output(argv[1], std::ios::binary | std::ios::trunc);
  output << getpid() << ' ' << (descriptors_closed ? "closed" : "open")
         << '\n';
  output.close();
  for (;;)
    pause();
}
