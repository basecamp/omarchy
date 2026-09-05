#include "activation_catalog.hpp"

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

std::string record(std::string_view plugin, char digest = 'a') {
  return "format=omarchy-plugin-activation-v2\nplugin=" + std::string(plugin) +
         "\nrevision-directory=revision\nrevision-sha256=" +
         std::string(64, digest) + "\nstate-directory=" +
         std::string(plugin) +
         "\n";
}

template <typename Value>
concept ExposesParsedRecord = requires(const Value &value) { value.record(); };
template <typename Value>
concept ExposesRecordDescriptor = requires(const Value &value) {
  value.inventory_record_fd();
};
template <typename Value>
concept ExposesRootDescriptor = requires(const Value &value) {
  value.activation_root_fd();
};
template <typename Value>
concept ExposesRecordName = requires(const Value &value) {
  value.record_name();
};
template <typename Value>
concept ExposesChangedAlias = requires(const Value &left,
                                       const Value &right) {
  left.changed_from(right);
};
template <typename Value>
concept ExposesPartialRootEpoch = requires(const Value &left,
                                           const Value &right) {
  left.same_root_epoch(right);
};
static_assert(!ExposesParsedRecord<catalog::ActivationCatalogEntry>);
static_assert(!ExposesRecordDescriptor<catalog::ActivationCatalogEntry>);
static_assert(!ExposesRootDescriptor<catalog::ActivationCatalog>);
static_assert(!ExposesRecordName<catalog::ActivationCatalogEntry>);
static_assert(!ExposesChangedAlias<catalog::ActivationCatalogEntry>);
static_assert(!ExposesChangedAlias<catalog::ActivationCatalog>);
static_assert(!ExposesPartialRootEpoch<catalog::ActivationCatalog>);

class Fixture final {
public:
  Fixture() {
    std::string pattern = "/tmp/omarchy-activation-catalog.XXXXXX";
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

  void overwrite(std::string_view name, std::string_view bytes) const {
    const auto path = root_ / std::string(name);
    const int descriptor =
        ::open(path.c_str(), O_WRONLY | O_TRUNC | O_CLOEXEC | O_NOFOLLOW);
    require(descriptor >= 0, "catalog record overwrite failed");
    std::size_t offset = 0;
    while (offset < bytes.size()) {
      const auto count =
          ::write(descriptor, bytes.data() + offset, bytes.size() - offset);
      require(count > 0, "catalog record overwrite write failed");
      offset += static_cast<std::size_t>(count);
    }
    require(::close(descriptor) == 0, "catalog overwrite close failed");
  }

  void erase(std::string_view name) const {
    require(std::filesystem::remove(root_ / std::string(name)),
            "catalog record removal failed");
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

std::unique_ptr<catalog::ActivationCatalog>
load(const Fixture &fixture, catalog::ActivationCatalogError &error,
     std::uint32_t uid = static_cast<std::uint32_t>(::getuid())) {
  const int root = fixture.open_root();
  auto result = catalog::ActivationCatalog::load(root, uid, error);
  ::close(root);
  return result;
}

void descriptor_and_format_rejections_are_typed() {
  {
    catalog::ActivationCatalogError error{};
    auto loaded = catalog::ActivationCatalog::load(
        -1, static_cast<std::uint32_t>(::getuid()), error);
    require(!loaded &&
                error == catalog::ActivationCatalogError::root_untrusted,
            "invalid catalog descriptor did not fail transactionally");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    const int record_fd = ::open((fixture.root() / "org.example.valid").c_str(),
                                 O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    require(record_fd >= 0, "non-directory root fixture open failed");
    catalog::ActivationCatalogError error{};
    auto loaded = catalog::ActivationCatalog::load(
        record_fd, static_cast<std::uint32_t>(::getuid()), error);
    ::close(record_fd);
    require(!loaded &&
                error == catalog::ActivationCatalogError::root_untrusted,
            "non-directory catalog descriptor did not fail transactionally");
  }

  for (const std::string &invalid_name :
       {std::string("Org.example.upper"), std::string("org..example"),
        std::string("org.example-"), std::string(129, 'a')}) {
    Fixture fixture;
    fixture.put(invalid_name);
    catalog::ActivationCatalogError error{};
    auto loaded = load(fixture, error);
    require(!loaded &&
                error ==
                    catalog::ActivationCatalogError::unexpected_entry,
            "invalid canonical plugin ID did not fail transactionally");
  }

  for (const std::string_view malformed :
       {std::string_view{},
        std::string_view("format=omarchy-plugin-activation-v2\nplugin=")}) {
    Fixture fixture;
    fixture.put_bytes("org.example.malformed", malformed);
    catalog::ActivationCatalogError error{};
    auto loaded = load(fixture, error);
    require(!loaded &&
                error == catalog::ActivationCatalogError::invalid_record,
            "malformed activation record did not fail transactionally");
  }
}

void valid_catalog_is_opaque_stable_and_sorted() {
  Fixture fixture;
  fixture.put("org.example.zeta");
  fixture.put("org.example.alpha");
  catalog::ActivationCatalogError error{};
  auto loaded = load(fixture, error);
  require(loaded && error == catalog::ActivationCatalogError::none &&
              loaded->entries().size() == 2,
          "valid descriptor catalog did not load");
  require(loaded->entries()[0].plugin_id() == "org.example.alpha" &&
              loaded->entries()[1].plugin_id() == "org.example.zeta",
          "catalog snapshot order is not deterministic");
  for (const auto &entry : loaded->entries()) {
    require(!entry.plugin_id().empty(), "catalog candidate label disappeared");
  }
  require(loaded->unchanged(), "fresh catalog epoch was already stale");

  auto same = load(fixture, error);
  require(same && same->unchanged() && loaded->same_epoch(*same) &&
              loaded->entries()[0].same_epoch(same->entries()[0]) &&
              loaded->entries()[1].same_epoch(same->entries()[1]),
          "unchanged scans did not compare as one opaque epoch");
}

void successful_scans_report_every_inventory_change() {
  {
    Fixture fixture;
    fixture.put("org.example.first");
    catalog::ActivationCatalogError error{};
    auto before = load(fixture, error);
    fixture.put("org.example.second");
    auto after = load(fixture, error);
    require(before && after && after->entries().size() == 2 &&
                !before->unchanged() && !before->same_epoch(*after),
            "successful scan did not make an added plugin meaningful");
  }
  {
    Fixture fixture;
    fixture.put("org.example.first");
    fixture.put("org.example.second");
    catalog::ActivationCatalogError error{};
    auto before = load(fixture, error);
    fixture.erase("org.example.second");
    auto after = load(fixture, error);
    require(before && after && after->entries().size() == 1 &&
                !before->unchanged() && !before->same_epoch(*after),
            "successful scan did not make a removed plugin meaningful");
  }
  {
    Fixture fixture;
    fixture.put("org.example.first");
    catalog::ActivationCatalogError error{};
    auto before = load(fixture, error);
    fixture.overwrite("org.example.first", record("org.example.first", 'b'));
    auto after = load(fixture, error);
    require(before && after && !before->unchanged() &&
                !before->same_epoch(*after) &&
                !before->entries()[0].same_epoch(after->entries()[0]),
            "in-place activation record change retained its opaque epoch");
  }
  {
    Fixture fixture;
    fixture.put("org.example.first");
    catalog::ActivationCatalogError error{};
    auto before = load(fixture, error);
    fixture.erase("org.example.first");
    fixture.put("org.example.first");
    auto after = load(fixture, error);
    require(before && after && !before->same_epoch(*after) &&
                !before->entries()[0].same_epoch(after->entries()[0]),
            "replacement activation record retained its opaque epoch");
  }
}

void failed_scan_never_replaces_the_callers_last_good_catalog() {
  Fixture fixture;
  fixture.put("org.example.stable");
  catalog::ActivationCatalogError error{};
  auto last_good = load(fixture, error);
  require(last_good && last_good->entries().size() == 1,
          "last-good catalog setup failed");
  const int unexpected =
      ::open((fixture.root() / ".staging").c_str(),
             O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  require(unexpected >= 0, "failed-scan fixture creation failed");
  ::close(unexpected);
  auto rejected = load(fixture, error);
  require(!rejected &&
              error == catalog::ActivationCatalogError::unexpected_entry &&
              last_good->entries().size() == 1 &&
              last_good->entries()[0].plugin_id() == "org.example.stable" &&
              !last_good->unchanged(),
          "failed scan erased or silently refreshed caller-owned inventory");
}

void metadata_and_entry_rejections_are_transactional() {
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::chmod(fixture.root().c_str(), 0755) == 0,
            "root mode mutation failed");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ActivationCatalogError::root_untrusted,
            "non-0700 catalog root was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error, static_cast<std::uint32_t>(::getuid()) + 1) &&
                error == catalog::ActivationCatalogError::root_untrusted,
            "wrong-owner catalog root was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::chmod((fixture.root() / "org.example.valid").c_str(), 0644) == 0,
            "record mode mutation failed");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ActivationCatalogError::invalid_record,
            "non-0600 activation record was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::filesystem::create_hard_link(fixture.root() / "org.example.valid",
                                      fixture.root() / "org.example.alias");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error),
            "hard-linked activation record was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.target");
    std::filesystem::create_symlink("org.example.target",
                                    fixture.root() / "org.example.link");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ActivationCatalogError::unexpected_entry,
            "activation-record symlink was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    std::filesystem::create_directory(fixture.root() / "org.example.dir");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ActivationCatalogError::unexpected_entry,
            "activation-record directory was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    require(::mkfifo((fixture.root() / "org.example.fifo").c_str(), 0600) == 0,
            "special-file fixture creation failed");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ActivationCatalogError::unexpected_entry,
            "activation-record special file was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.valid");
    const int unknown = ::open((fixture.root() / ".staging").c_str(),
                               O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
    require(unknown >= 0, "unknown-entry fixture creation failed");
    ::close(unknown);
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error ==
                    catalog::ActivationCatalogError::unexpected_entry,
            "unknown catalog entry was ignored");
  }
  {
    Fixture fixture;
    fixture.put("org.example.actual", "org.example.other");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ActivationCatalogError::invalid_record,
            "filename and record plugin mismatch was accepted");
  }
  {
    Fixture fixture;
    fixture.put("org.example.first");
    fixture.put("org.example.alias", "org.example.first");
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error), "duplicate plugin identity was accepted");
  }
}

void bounds_and_mutation_fail_closed() {
  {
    Fixture fixture;
    for (std::size_t index = 0;
         index <= catalog::kMaximumActivationCatalogEntries; ++index) {
      fixture.put("org.example.plugin" + std::to_string(index));
    }
    catalog::ActivationCatalogError error{};
    require(!load(fixture, error) &&
                error == catalog::ActivationCatalogError::bound_exceeded,
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
      catalog::ActivationCatalogError error{};
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
      catalog::ActivationCatalogError error{};
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
    valid_catalog_is_opaque_stable_and_sorted();
    successful_scans_report_every_inventory_change();
    failed_scan_never_replaces_the_callers_last_good_catalog();
    descriptor_and_format_rejections_are_typed();
    metadata_and_entry_rejections_are_transactional();
    bounds_and_mutation_fail_closed();
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "activation catalog test failed: " << error.what()
              << '\n';
    return 1;
  }
}
