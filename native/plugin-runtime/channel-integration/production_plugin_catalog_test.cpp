#include "production_plugin_catalog.hpp"

#include <atomic>
#include <fcntl.h>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

namespace catalog = omarchy::plugin_runtime::channel;

namespace {

void require(bool condition, std::string_view message) {
  if (!condition)
    throw std::runtime_error(std::string(message));
}

std::string record(std::string_view plugin) {
  return "format=omarchy-plugin-activation-v2\nplugin=" + std::string(plugin) +
         "\nrevision-directory=revision\nrevision-sha256=" +
         std::string(64, 'a') + "\nstate-directory=" + std::string(plugin) +
         "\n";
}

class Fixture final {
public:
  Fixture() {
    std::string pattern = "/tmp/omarchy-production-catalog.XXXXXX";
    const auto *created = ::mkdtemp(pattern.data());
    require(created != nullptr, "catalog fixture creation failed");
    root_ = created;
  }

  ~Fixture() {
    std::error_code ignored;
    std::filesystem::remove_all(root_, ignored);
  }

  void put(std::string_view name, std::string_view plugin = {}) const {
    put_bytes(name, record(plugin.empty() ? name : plugin));
  }

  void put_bytes(std::string_view name, std::string_view bytes) const {
    const auto path = root_ / std::string(name);
    const int descriptor =
        ::open(path.c_str(),
               O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
    require(descriptor >= 0, "catalog record creation failed");
    std::size_t offset = 0;
    while (offset < bytes.size()) {
      const auto count =
          ::write(descriptor, bytes.data() + offset, bytes.size() - offset);
      require(count > 0, "catalog record write failed");
      offset += static_cast<std::size_t>(count);
    }
    require(::close(descriptor) == 0, "catalog record close failed");
  }

  [[nodiscard]] int open_root() const {
    const int descriptor =
        ::open(root_.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    require(descriptor >= 0, "catalog root open failed");
    return descriptor;
  }

  [[nodiscard]] const std::filesystem::path &root() const { return root_; }

private:
  std::filesystem::path root_;
};

std::unique_ptr<catalog::ProductionPluginCatalog>
load(const Fixture &fixture, catalog::ProductionPluginCatalogError &error,
     std::uint32_t uid = static_cast<std::uint32_t>(::getuid())) {
  const int root = fixture.open_root();
  auto result = catalog::ProductionPluginCatalog::load(root, uid, error);
  ::close(root);
  return result;
}

void descriptor_and_format_rejections_are_typed() {
  {
    catalog::ProductionPluginCatalogError error{};
    auto loaded = catalog::ProductionPluginCatalog::load(
        -1, static_cast<std::uint32_t>(::getuid()), error);
    require(!loaded &&
                error == catalog::ProductionPluginCatalogError::root_untrusted,
            "invalid catalog descriptor did not fail transactionally");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    const int record_fd = ::open((fixture.root() / "org.example.valid").c_str(),
                                 O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    require(record_fd >= 0, "non-directory root fixture open failed");
    catalog::ProductionPluginCatalogError error{};
    auto loaded = catalog::ProductionPluginCatalog::load(
        record_fd, static_cast<std::uint32_t>(::getuid()), error);
    ::close(record_fd);
    require(!loaded &&
                error == catalog::ProductionPluginCatalogError::root_untrusted,
            "non-directory catalog descriptor did not fail transactionally");
  }

  for (const std::string &invalid_name :
       {std::string("Org.example.upper"), std::string("org..example"),
        std::string("org.example-"), std::string(129, 'a')}) {
    Fixture fixture;
    fixture.put(invalid_name);
    catalog::ProductionPluginCatalogError error{};
    auto loaded = load(fixture, error);
    require(!loaded &&
                error ==
                    catalog::ProductionPluginCatalogError::unexpected_entry,
            "invalid canonical plugin ID did not fail transactionally");
  }

  for (const std::string_view malformed :
       {std::string_view{},
        std::string_view("format=omarchy-plugin-activation-v2\nplugin=")}) {
    Fixture fixture;
    fixture.put_bytes("org.example.malformed", malformed);
    catalog::ProductionPluginCatalogError error{};
    auto loaded = load(fixture, error);
    require(!loaded &&
                error == catalog::ProductionPluginCatalogError::invalid_record,
            "malformed activation record did not fail transactionally");
  }
}

void valid_catalog_is_pinned_and_sorted() {
  Fixture fixture;
  fixture.put("org.example.zeta");
  fixture.put("org.example.alpha");
  catalog::ProductionPluginCatalogError error{};
  auto loaded = load(fixture, error);
  require(loaded && error == catalog::ProductionPluginCatalogError::none &&
              loaded->entries().size() == 2,
          "valid descriptor catalog did not load");
  require(loaded->entries()[0].record_name() == "org.example.alpha" &&
              loaded->entries()[1].record_name() == "org.example.zeta",
          "catalog snapshot order is not deterministic");
  for (const auto &entry : loaded->entries()) {
    require(
        entry.record_name() == entry.record().plugin_id && entry.unchanged() &&
            (::fcntl(entry.inventory_record_fd(), F_GETFD) & FD_CLOEXEC) != 0,
        "catalog entry lost exact pinned identity");
  }
  require((::fcntl(loaded->activation_root_fd(), F_GETFD) & FD_CLOEXEC) != 0,
          "catalog root is not independently pinned close-on-exec");

  struct stat before{};
  require(::fstat(loaded->entries()[0].inventory_record_fd(), &before) == 0,
          "catalog record pre-replacement fstat failed");
  std::filesystem::rename(fixture.root() / "org.example.alpha",
                          fixture.root() / "moved");
  fixture.put("org.example.alpha");
  struct stat after{};
  require(loaded->entries()[0].record().plugin_id == "org.example.alpha" &&
              ::fstat(loaded->entries()[0].inventory_record_fd(), &after) ==
                  0 &&
              before.st_dev == after.st_dev && before.st_ino == after.st_ino,
          "path replacement retargeted a catalog entry");
  require(!loaded->entries()[0].unchanged(),
          "catalog did not report its post-snapshot path mutation");
}

void metadata_and_entry_rejections_are_transactional() {
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::chmod(fixture.root().c_str(), 0755) == 0,
            "root mode mutation failed");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ProductionPluginCatalogError::root_untrusted,
            "non-0700 catalog root was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error, static_cast<std::uint32_t>(::getuid()) + 1) &&
                error == catalog::ProductionPluginCatalogError::root_untrusted,
            "wrong-owner catalog root was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::chmod((fixture.root() / "org.example.valid").c_str(), 0644) == 0,
            "record mode mutation failed");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ProductionPluginCatalogError::invalid_record,
            "non-0600 activation record was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::filesystem::create_hard_link(fixture.root() / "org.example.valid",
                                      fixture.root() / "org.example.alias");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error),
            "hard-linked activation record was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.target");
    std::filesystem::create_symlink("org.example.target",
                                    fixture.root() / "org.example.link");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ProductionPluginCatalogError::unexpected_entry,
            "activation-record symlink was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::filesystem::create_directory(fixture.root() / "org.example.dir");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ProductionPluginCatalogError::unexpected_entry,
            "activation-record directory was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::mkfifo((fixture.root() / "org.example.fifo").c_str(), 0600) == 0,
            "special-file fixture creation failed");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ProductionPluginCatalogError::unexpected_entry,
            "activation-record special file was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    const int unknown = ::open((fixture.root() / ".staging").c_str(),
                               O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
    require(unknown >= 0, "unknown-entry fixture creation failed");
    ::close(unknown);
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ProductionPluginCatalogError::unexpected_entry,
            "unknown catalog entry was ignored");
  }
  {
    Fixture fixture;
    fixture.put("org.example.actual", "org.example.other");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ProductionPluginCatalogError::invalid_record,
            "filename and record plugin mismatch was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.first");
    fixture.put("org.example.alias", "org.example.first");
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error), "duplicate plugin identity was accepted");
  }
}

void bounds_and_mutation_fail_closed() {
  {
    Fixture fixture;
    for (std::size_t index = 0;
         index <= catalog::kMaximumProductionPluginCatalogEntries; ++index) {
      fixture.put("org.example.plugin" + std::to_string(index));
    }
    catalog::ProductionPluginCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ProductionPluginCatalogError::bound_exceeded,
            "catalog entry bound was not enforced");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::atomic<bool> run{true};
    std::atomic<std::size_t> mutations{0};
    std::thread mutator([&] {
      const auto path = fixture.root() / "org.example.valid";
      while (run.load(std::memory_order_acquire)) {
        ::chmod(path.c_str(), 0400);
        ::chmod(path.c_str(), 0600);
        mutations.fetch_add(1, std::memory_order_release);
      }
    });
    while (mutations.load(std::memory_order_acquire) < 100) {
    }
    bool rejected = false;
    for (int attempt = 0; attempt < 100 && !rejected; ++attempt) {
      catalog::ProductionPluginCatalogError error{};
      rejected = !load(fixture, error);
    }
    run.store(false, std::memory_order_release);
    mutator.join();
    require(rejected,
            "concurrent activation-record mutation was never rejected");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::atomic<bool> run{true};
    std::atomic<std::size_t> mutations{0};
    std::thread mutator([&] {
      const auto path = fixture.root() / "churn";
      while (run.load(std::memory_order_acquire)) {
        const int descriptor =
            ::open(path.c_str(), O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
        if (descriptor >= 0)
          ::close(descriptor);
        ::unlink(path.c_str());
        mutations.fetch_add(1, std::memory_order_release);
      }
    });
    while (mutations.load(std::memory_order_acquire) < 100) {
    }
    bool rejected = false;
    for (int attempt = 0; attempt < 100 && !rejected; ++attempt) {
      catalog::ProductionPluginCatalogError error{};
      rejected = !load(fixture, error);
    }
    run.store(false, std::memory_order_release);
    mutator.join();
    std::filesystem::remove(fixture.root() / "churn");
    require(rejected, "concurrent catalog mutation was never rejected");
  }
}

} // namespace

int main() {
  try {
    valid_catalog_is_pinned_and_sorted();
    descriptor_and_format_rejections_are_typed();
    metadata_and_entry_rejections_are_transactional();
    bounds_and_mutation_fail_closed();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "production plugin catalog test failed: " << error.what()
              << '\n';
    return 1;
  }
}
