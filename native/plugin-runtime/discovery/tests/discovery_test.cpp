#include "discovery.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>

namespace discovery = omarchy::plugins::discovery;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

class TemporaryDirectory {
public:
  TemporaryDirectory() {
    std::string pattern =
        (std::filesystem::temp_directory_path() / "omarchy-c0-XXXXXX").string();
    path_ = mkdtemp(pattern.data());
    require(!path_.empty(), "temporary directory creation failed");
  }
  ~TemporaryDirectory() {
    std::error_code error;
    std::filesystem::remove_all(path_, error);
  }
  const std::filesystem::path &path() const { return path_; }

private:
  std::filesystem::path path_;
};

void copy_tree(const std::filesystem::path &source,
               const std::filesystem::path &destination) {
  std::filesystem::create_directories(destination);
  for (const auto &entry : std::filesystem::directory_iterator(source)) {
    std::filesystem::copy(
        entry.path(), destination / entry.path().filename(),
        std::filesystem::copy_options::recursive |
            std::filesystem::copy_options::overwrite_existing);
  }
}

template <typename Function>
void expect_rejected(Function &&function, std::string_view message) {
  try {
    function();
  } catch (const std::exception &) {
    return;
  }
  throw std::runtime_error(std::string(message));
}

int open_directory(const std::filesystem::path &path) {
  return ::open(path.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
}

} // namespace

int main() {
  try {
    expect_rejected(
        [] { (void)discovery::discover_open_revision(-1); },
        "descriptor discovery accepted an invalid descriptor");

    TemporaryDirectory verified_root;
    const auto original_path = verified_root.path() / "secure";
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, original_path);
    const int stable_fd = open_directory(original_path);
    require(stable_fd >= 0, "could not open stable plugin descriptor");
    const auto descriptor_result = discovery::discover_open_revision(stable_fd);
    require(descriptor_result.manifest.id == "org.example.status" &&
                descriptor_result.identity.tree_sha256 == TREE_SHA256_GOLDEN,
            "descriptor discovery changed the canonical fixture identity");
    require(discovery::discover_open_revision(stable_fd).identity ==
                descriptor_result.identity,
            "descriptor discovery changed the caller's directory position");

    const auto displaced_path = verified_root.path() / "displaced";
    std::filesystem::rename(original_path, displaced_path);
    copy_tree(MANIFEST_DUPLICATE_FIXTURE_ROOT, original_path);
    const auto after_replacement = discovery::discover_open_revision(stable_fd);
    require(after_replacement.identity == descriptor_result.identity &&
                after_replacement.manifest == descriptor_result.manifest,
            "pathname replacement retargeted descriptor discovery");
    ::close(stable_fd);

    TemporaryDirectory special_root;
    const auto special_plugin = special_root.path() / "special";
    std::filesystem::create_directory(special_plugin);
    require(::mkfifo((special_plugin / "manifest.json").c_str(), 0600) == 0,
            "manifest FIFO creation failed");
    const int special_fd = open_directory(special_plugin);
    require(special_fd >= 0, "could not open special plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(special_fd); },
        "descriptor discovery admitted a special file");
    ::close(special_fd);

    TemporaryDirectory symlink_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, symlink_root.path() / "linked");
    std::filesystem::create_symlink("ui/Status.qml",
                                    symlink_root.path() / "linked/escape");
    const int symlink_fd = open_directory(symlink_root.path() / "linked");
    require(symlink_fd >= 0, "could not open symlink plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(symlink_fd); },
        "descriptor discovery admitted a symlink");
    ::close(symlink_fd);

    TemporaryDirectory git_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, git_root.path() / "checkout");
    std::filesystem::create_directories(git_root.path() / "checkout/.git");
    std::ofstream(git_root.path() / "checkout/.git/config")
        << "untrusted metadata\n";
    const int git_fd = open_directory(git_root.path() / "checkout");
    require(git_fd >= 0, "could not open .git plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(git_fd); },
        "descriptor discovery excluded sandbox-visible .git content");
    ::close(git_fd);

    TemporaryDirectory oversized_manifest_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT,
              oversized_manifest_root.path() / "oversized");
    {
      std::ofstream manifest_file(oversized_manifest_root.path() /
                                  "oversized/manifest.json");
      manifest_file << std::string(1024 * 1024 + 1, ' ');
    }
    const int oversized_manifest_fd =
        open_directory(oversized_manifest_root.path() / "oversized");
    require(oversized_manifest_fd >= 0,
            "could not open oversized-manifest plugin descriptor");
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(oversized_manifest_fd); },
        "descriptor discovery admitted an oversized manifest");
    ::close(oversized_manifest_fd);

    TemporaryDirectory changing_root;
    copy_tree(MANIFEST_V2_FIXTURE_ROOT, changing_root.path() / "changing");
    {
      std::ofstream padding(changing_root.path() / "changing/padding");
      padding << std::string(8 * 1024 * 1024, 'x');
    }
    const int changing_fd = open_directory(changing_root.path() / "changing");
    require(changing_fd >= 0, "could not open changing plugin descriptor");
    std::atomic_bool mutate{true};
    std::atomic_bool first_mutation{false};
    std::jthread mutator([&] {
      const auto marker = changing_root.path() / "changing/mutation";
      while (mutate.load(std::memory_order_relaxed)) {
        std::ofstream(marker) << "changed";
        std::filesystem::remove(marker);
        first_mutation.store(true, std::memory_order_release);
      }
    });
    while (!first_mutation.load(std::memory_order_acquire))
      std::this_thread::yield();
    expect_rejected(
        [&] { (void)discovery::discover_open_revision(changing_fd); },
        "descriptor discovery admitted a concurrently changing tree");
    mutate.store(false, std::memory_order_relaxed);
    mutator.join();
    ::close(changing_fd);

    std::cout << "descriptor plugin discovery: PASS\n";
    return 0;
  } catch (const std::exception &exception) {
    std::cerr << "descriptor plugin discovery: FAIL: " << exception.what()
              << '\n';
    return 1;
  }
}
