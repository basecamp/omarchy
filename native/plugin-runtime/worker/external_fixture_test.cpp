#include "capability_definition_loader.hpp"
#include "manifest_contract.hpp"
#include "worker_runtime.hpp"

#include <QGuiApplication>
#include <QObject>
#include <QStringList>
#include <QVariantMap>

#include <fcntl.h>
#include <linux/memfd.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <ranges>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
namespace definitions = omarchy::plugins::definitions;
namespace manifest = omarchy::plugins::manifest;
namespace permissions = omarchy::plugins::permissions;
namespace surface = omarchy::plugin_runtime::surface;
namespace worker = omarchy::plugin_runtime::worker;

void require(bool condition, const std::string &message) {
  if (!condition)
    throw std::runtime_error(message);
}

std::string read_file(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  require(input.good(), "cannot read " + path.string());
  return {std::istreambuf_iterator<char>(input), {}};
}

struct RegisteredAdapter {
  definitions::AdapterBinding binding;
};

std::vector<RegisteredAdapter> parse_adapters(std::string_view value) {
  std::vector<RegisteredAdapter> result;
  while (!value.empty()) {
    const auto end = value.find(';');
    const auto item = value.substr(0, end);
    const auto first = item.find(':');
    const auto second = item.find(':', first + 1);
    require(first != std::string_view::npos && second != std::string_view::npos,
            "adapter registration must be class:digest:abi");
    const auto abi_text = item.substr(second + 1);
    std::size_t consumed = 0;
    const auto abi = std::stoul(std::string(abi_text), &consumed);
    require(consumed == abi_text.size() && abi > 0 && abi <= UINT32_MAX,
            "adapter registration ABI is invalid");
    result.push_back(
        {.binding = {.adapter_class = definitions::Name(item.substr(0, first)),
                     .implementation_digest = definitions::Digest(
                         item.substr(first + 1, second - first - 1)),
                     .abi_version = static_cast<std::uint32_t>(abi)}});
    if (end == std::string_view::npos)
      break;
    value.remove_prefix(end + 1);
  }
  require(!result.empty(), "no trusted adapters were registered");
  return result;
}

bool adapter_available(std::string_view adapter_class,
                       const definitions::Digest &digest, std::uint32_t abi,
                       void *context) noexcept {
  const auto &adapters =
      *static_cast<const std::vector<RegisteredAdapter> *>(context);
  return std::ranges::any_of(adapters, [&](const auto &registered) {
    return registered.binding.adapter_class.view() == adapter_class &&
           registered.binding.implementation_digest == digest &&
           registered.binding.abi_version == abi;
  });
}

struct Binding {
  definitions::DynamicRequest request;
  definitions::DynamicGrant grant;
  definitions::AdapterBinding adapter;
};

definitions::DynamicScopeRelation
exact_scope(const definitions::CapabilityDefinition &,
            std::string_view candidate, std::string_view baseline,
            void *) noexcept {
  return candidate == baseline
             ? definitions::DynamicScopeRelation::equal
             : definitions::DynamicScopeRelation::incomparable;
}

std::vector<Binding>
resolve_requests(const manifest::ManifestV2 &plugin,
                 const definitions::TrustedDefinitionRegistry &registry,
                 const std::vector<RegisteredAdapter> &adapters) {
  std::vector<Binding> result;
  for (const auto &request : plugin.requests) {
    if (request.definition_generation == 0) {
      require(request.capability == "storage.private" ||
                  request.capability == "notifications.send" ||
                  request.capability == "audio.play-cue",
              "manifest capability is neither compiled nor exactly defined");
      continue;
    }
    require(request.definition_generation > 0 &&
                request.definition_digest.size() == 64 &&
                !request.operations.empty(),
            "manifest capability lacks an exact trusted definition reference");
    definitions::CapabilityReference reference{
        .canonical_name = definitions::Name(request.capability),
        .definition_generation = request.definition_generation,
        .definition_digest = definitions::Digest(request.definition_digest)};
    const auto resolved = registry.resolve(reference);
    require(resolved.has_value(),
            "manifest capability is unknown, stale, or digest-mismatched: " +
                request.capability);
    const auto translated =
        definitions::dynamic_request_from_manifest(request, registry);
    require(translated.has_value(),
            "manifest request did not translate through trusted registry");
    Binding binding{.request = *translated,
                    .grant = {.definition = reference,
                              .operations = {},
                              .scope = translated->scope,
                              .state = permissions::GrantState::granted,
                              .epoch = 1},
                    .adapter = resolved->definition->adapter};
    for (const auto &operation : request.operations) {
      require(binding.grant.operations.insert(definitions::Name(operation)),
              "duplicate granted operation");
    }
    require(std::ranges::any_of(adapters,
                                [&](const auto &registered) {
                                  return registered.binding == binding.adapter;
                                }),
            "definition's exact adapter class/digest/ABI is not registered");
    result.push_back(std::move(binding));
  }
  return result;
}

std::vector<std::string>
compiled_operations(const manifest::ManifestV2 &plugin) {
  std::vector<std::string> result;
  for (const auto &request : plugin.requests) {
    if (request.definition_generation != 0)
      continue;
    if (request.capability == "storage.private")
      result.insert(result.end(), {"storage_read", "storage_write",
                                   "storage_remove"});
    else if (request.capability == "notifications.send")
      result.push_back("notification_send");
    else if (request.capability == "audio.play-cue")
      result.push_back("audio_play_cue");
  }
  return result;
}

class StrictRuntime final : public QObject {
  Q_OBJECT
public:
  StrictRuntime(const definitions::TrustedDefinitionRegistry &registry,
                std::vector<Binding> bindings,
                std::vector<std::string> compiled)
      : registry_(registry), bindings_(std::move(bindings)),
        compiled_(std::move(compiled)) {}

  Q_INVOKABLE QVariant invoke(const QString &operation,
                              const QVariantMap &arguments) {
    (void)arguments;
    const auto name = operation.toStdString();
    if (std::ranges::find(compiled_, name) != compiled_.end())
      return QVariantMap{{QStringLiteral("ok"), true}};
    bool registered = false;
    for (const auto &binding : bindings_) {
      const auto resolved = registry_.resolve(binding.request.definition);
      if (resolved &&
          std::ranges::any_of(
              resolved->definition->operations.values(),
              [&](const auto &defined) { return defined.name.view() == name; }))
        registered = true;
      const definitions::DynamicScopeValidator scopes{.compare = exact_scope};
      const auto decision = definitions::authorize_dynamic_operation(
          registry_, binding.request, binding.grant, name,
          binding.request.scope.view(), binding.adapter, scopes, false);
      if (decision.allowed())
        return QVariantMap{{QStringLiteral("ok"), true}};
    }
    return QVariantMap{{QStringLiteral("ok"), false},
                       {QStringLiteral("error"),
                        registered ? QStringLiteral("permission-denied")
                                   : QStringLiteral("unknown-operation")}};
  }

private:
  const definitions::TrustedDefinitionRegistry &registry_;
  std::vector<Binding> bindings_;
  std::vector<std::string> compiled_;
};

class Mapping {
public:
  Mapping(int descriptor, std::size_t size) : size_(size) {
    address_ = static_cast<std::byte *>(
        mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0));
    require(address_ != MAP_FAILED, "frame mapping failed");
  }
  ~Mapping() {
    if (address_ != MAP_FAILED)
      munmap(address_, size_);
  }
  std::span<const std::byte> bytes() const { return {address_, size_}; }

private:
  std::byte *address_ = reinterpret_cast<std::byte *>(MAP_FAILED);
  std::size_t size_ = 0;
};

void run(const std::filesystem::path &root, std::string_view function,
         const std::filesystem::path &definition_root,
         std::string_view adapter_text) {
  auto adapters = parse_adapters(adapter_text);
  definitions::TrustedDefinitionRegistry registry;
  std::size_t loaded = 0;
  const definitions::AdapterVerifier verifier{.available = adapter_available,
                                              .context = &adapters};
  require(definitions::load_definition_directory(
              definition_root.string(),
              definitions::DefinitionSource::local_admin,
              static_cast<std::uint32_t>(getuid()), verifier, registry,
              loaded) == definitions::LoadResult::loaded &&
              loaded > 0,
          "independent trusted definition set failed to load");
  const auto plugin =
      manifest::parse_manifest_v2(read_file(root / "manifest.json"));
  auto bindings = resolve_requests(plugin, registry, adapters);
  auto compiled = compiled_operations(plugin);
  require(!bindings.empty() || !compiled.empty(),
          "external fixture requests no brokered capabilities");

  if (!bindings.empty()) {
    auto stale = bindings.front().request.definition;
    ++stale.definition_generation;
    require(!registry.resolve(stale), "stale definition generation resolved");
    auto mutated_digest = bindings.front().request.definition;
    const std::string wrong_digest(64, 'f');
    if (mutated_digest.definition_digest.view() == wrong_digest)
      mutated_digest.definition_digest =
          definitions::Digest(std::string(64, 'e'));
    else
      mutated_digest.definition_digest = definitions::Digest(wrong_digest);
    require(!registry.resolve(mutated_digest),
            "mismatched definition digest resolved");
    require(!registry.find("winner.plugin-freeform"),
            "plugin-only freeform definition entered trusted registry");

    auto wrong_adapter = bindings.front().adapter;
    wrong_adapter.implementation_digest = definitions::Digest(
        wrong_adapter.implementation_digest.view() == wrong_digest
            ? std::string(64, 'e')
            : wrong_digest);
    const definitions::DynamicScopeValidator scopes{.compare = exact_scope};
    const auto adapter_denial = definitions::authorize_dynamic_operation(
        registry, bindings.front().request, bindings.front().grant,
        bindings.front().request.operations.values().front().view(),
        bindings.front().request.scope.view(), wrong_adapter, scopes, false);
    require(adapter_denial.decision ==
                definitions::DynamicDecision::adapter_mismatch,
            "adapter implementation digest mismatch was authorized");
  }

  StrictRuntime provider(registry, std::move(bindings), std::move(compiled));
  const auto unknown =
      provider.invoke(QStringLiteral("winner.magic"), {}).toMap();
  require(!unknown.value(QStringLiteral("ok")).toBool() &&
              unknown.value(QStringLiteral("error")).toString() ==
                  QStringLiteral("unknown-operation"),
          "unregistered winner operation acquired authority");

  worker::WorkerRuntime runtime(root);
  require(static_cast<bool>(runtime.bind_runtime_api(provider)),
          "strict runtime provider binding failed");
  const auto loaded_qml = runtime.load_manifest_entry();
  require(static_cast<bool>(loaded_qml),
          "fixture QML failed to load: " + loaded_qml.detail);
  require(runtime.object_count() > 1 && runtime.invoke_test_function(function),
          "fixture scene or deterministic function is unavailable");
  require(static_cast<bool>(runtime.select_software_profile(
              surface::software_profile_offer())),
          "fixture rejected software rendering");
  const auto page_size = sysconf(_SC_PAGESIZE);
  const auto allocation = surface::make_allocation(
      {.id = 700, .generation = 1}, 1280, 720, 1280, 720, 1, 1,
      static_cast<std::uint64_t>(page_size));
  require(page_size > 0 && allocation, "fixture frame allocation failed");
  const int descriptor = static_cast<int>(
      syscall(SYS_memfd_create, "external-fixture-frame", MFD_CLOEXEC));
  require(descriptor >= 0 &&
              ftruncate(descriptor,
                        static_cast<off_t>(allocation->mapping_bytes)) == 0,
          "fixture frame memfd failed");
  Mapping mapping(descriptor, allocation->mapping_bytes);
  const int worker_descriptor = fcntl(descriptor, F_DUPFD_CLOEXEC, 64);
  close(descriptor);
  require(worker_descriptor >= 0 &&
              runtime.allocate(*allocation, worker_descriptor),
          "worker rejected fixture allocation");
  const auto frame = runtime.render();
  auto consumer = surface::FrameConsumer::create(*allocation);
  require(frame && consumer &&
              consumer->consume(mapping.bytes(), frame->ready) ==
                  surface::ConsumeResult::accepted &&
              std::ranges::any_of(
                  consumer->last_frame()->pixels,
                  [](std::byte value) { return value != std::byte{0}; }),
          "fixture did not publish non-transparent trusted pixels");
}
} // namespace

int main(int argc, char **argv) {
  try {
    QGuiApplication application(argc, argv);
    const QStringList args = application.arguments();
    require(args.size() == 9 && args.at(1) == "--root" &&
                args.at(3) == "--function" && args.at(5) == "--definitions" &&
                args.at(7) == "--adapters",
            "usage: external-fixture-test --root PATH --function NAME "
            "--definitions PATH --adapters CLASS:DIGEST:ABI[;...]");
    run(args.at(2).toStdString(), args.at(4).toStdString(),
        args.at(6).toStdString(), args.at(8).toStdString());
    std::cout << "external plugin fixture: ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << "external plugin fixture: " << error.what() << '\n';
    return 1;
  }
}

#include "external_fixture_test.moc"
