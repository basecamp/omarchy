#include "revision_verifier_adapter.hpp"

#include "discovery.hpp"

#include <fcntl.h>
#include <unistd.h>

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

namespace discovery = omarchy::plugins::discovery;
namespace host = omarchy::plugin_runtime::host_session;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class Descriptor {
public:
  explicit Descriptor(const std::filesystem::path &path)
      : value_(::open(path.c_str(),
                      O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)) {
    require(value_ >= 0, "could not open fixture directory");
  }
  ~Descriptor() { ::close(value_); }
  [[nodiscard]] int get() const { return value_; }

private:
  int value_;
};

} // namespace

int main() {
  try {
    const std::filesystem::path fixture = MANIFEST_V2_FIXTURE_ROOT;
    Descriptor descriptor(fixture);
    const auto direct = discovery::discover_open_revision(descriptor.get());
    const host::SourceRevisionVerifier verifier;
    const auto adapted = verifier.verify_open_revision(descriptor.get());
    require(adapted && adapted->manifest == direct.manifest &&
                adapted->tree_sha256 == direct.identity.tree_sha256 &&
                adapted->request_sha256 == direct.identity.request_sha256,
            "revision verifier did not preserve descriptor discovery identity");
    require(!verifier.verify_open_revision(-1),
            "revision verifier admitted an invalid descriptor");
    std::cout << "descriptor revision verifier adapter: PASS\n";
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "descriptor revision verifier adapter: FAIL: "
              << exception.what() << '\n';
    return 1;
  }
}
