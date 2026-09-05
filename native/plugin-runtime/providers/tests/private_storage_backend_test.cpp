#include "omarchy/plugin_runtime/providers/private_storage_backend.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <array>
#include <cstddef>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace providers = omarchy::plugin_runtime::providers;

namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
} // namespace

int main() {
  char path[] = "/tmp/omarchy-private-store-XXXXXX";
  require(mkdtemp(path) != nullptr, "temporary directory failed");
  const std::filesystem::path root(path);
  struct Cleanup {
    std::filesystem::path path;
    ~Cleanup() { std::filesystem::remove_all(path); }
  } cleanup{root};
  const int directory = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  require(directory >= 0, "open directory failed");
  providers::PrivateStorageBackend storage(directory, 8, 6);
  close(directory);
  require(storage.valid(), "backend did not duplicate directory fd");
  auto backend = storage.configuration();
  const std::array value{std::byte{1}, std::byte{2}, std::byte{3}};
  require(backend.write("widget-state", value, backend.context), "write failed");
  std::array<std::byte, 8> output{};
  std::size_t written = 0;
  bool found = false;
  require(backend.read("widget-state", output, written, found, backend.context) &&
              found && written == value.size() && output[2] == value[2],
          "read failed");
  const std::array second{std::byte{4}, std::byte{5}, std::byte{6},
                          std::byte{7}, std::byte{8}, std::byte{9}};
  require(!backend.write("other", second, backend.context),
          "total quota was exceeded");
  const int fixture_directory =
      open(root.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  require(fixture_directory >= 0 &&
              symlinkat("/etc/passwd", fixture_directory, "escape") == 0,
          "symlink fixture failed");
  close(fixture_directory);
  require(!backend.read("escape", output, written, found, backend.context),
          "symlink escaped private storage");
  require(!backend.write("../escape", value, backend.context),
          "path-like key escaped private storage");
  require(backend.remove("widget-state", backend.context), "remove failed");
  require(backend.read("widget-state", output, written, found, backend.context) &&
              !found,
          "missing read failed");
}
