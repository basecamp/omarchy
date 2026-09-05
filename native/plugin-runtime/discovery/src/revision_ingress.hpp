#pragma once

#include "discovery.hpp"

#include <cstdint>

namespace omarchy::plugins::discovery {

// One immutable revision opened from the exact object published below the
// caller-owned revisions root. The descriptor remains authoritative; callers
// need not reopen the digest as a path.
class PublishedRevision final {
public:
  PublishedRevision(PublishedRevision &&other) noexcept;
  PublishedRevision &operator=(PublishedRevision &&other) noexcept;
  ~PublishedRevision();
  PublishedRevision(const PublishedRevision &) = delete;
  PublishedRevision &operator=(const PublishedRevision &) = delete;

  [[nodiscard]] int descriptor() const noexcept { return descriptor_; }
  [[nodiscard]] const DescriptorVerifiedPlugin &verified() const noexcept {
    return verified_;
  }
private:
  PublishedRevision(int descriptor, DescriptorVerifiedPlugin verified) noexcept;

  int descriptor_ = -1;
  DescriptorVerifiedPlugin verified_;

  friend PublishedRevision publish_revision_archive(int, int, std::uint32_t);
};

// Extract one untrusted ustar archive into private descriptor-rooted staging,
// verify its exact immutable tree, and publish it under its content digest.
// The revisions root is borrowed. Failures throw std::runtime_error and never
// create or modify activation or authority records.
[[nodiscard]] PublishedRevision publish_revision_archive(
    int archive_fd, int revisions_root_fd, std::uint32_t expected_uid);

#ifdef OMARCHY_REVISION_INGRESS_TESTING
enum class RevisionIngressCrashPoint {
  none,
  extracted,
  verified,
  durable,
  renamed,
  published,
};
void set_revision_ingress_crash_point_for_testing(
    RevisionIngressCrashPoint point) noexcept;
#endif

} // namespace omarchy::plugins::discovery
