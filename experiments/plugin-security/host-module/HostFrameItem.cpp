#include "HostFrameItem.h"

#include <QCryptographicHash>

#include <cerrno>
#include <climits>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

constexpr qsizetype bytesPerPixel = 4;
constexpr qsizetype maximumDimension = 4096;
constexpr qsizetype maximumFrameBytes = 64 * 1024 * 1024;

class OwnedFd {
public:
  explicit OwnedFd(int fd) : m_fd(fd) {}
  ~OwnedFd() {
    if (m_fd >= 0) {
      close(m_fd);
    }
  }

  OwnedFd(const OwnedFd &) = delete;
  OwnedFd &operator=(const OwnedFd &) = delete;

  [[nodiscard]] int get() const { return m_fd; }

private:
  int m_fd;
};

} // namespace

HostFrameItem::HostFrameItem(QQuickItem *parent) : QQuickItem(parent) {
  setFlag(ItemHasContents, false);
}

QImage HostFrameItem::frame() const { return m_frame; }

QString HostFrameItem::frameDigest() const {
  if (m_frame.isNull()) {
    return {};
  }

  const QByteArray bytes(reinterpret_cast<const char *>(m_frame.constBits()),
                         static_cast<qsizetype>(m_frame.sizeInBytes()));
  return QString::fromLatin1(
      QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex());
}

QString HostFrameItem::lastError() const { return m_lastError; }

quint64 HostFrameItem::surfaceGeneration() const { return m_surfaceGeneration; }

bool HostFrameItem::configureSurface(int width, int height, qint64 offset) {
  if (width <= 0 || height <= 0 || width > maximumDimension ||
      height > maximumDimension) {
    return reject(
        QStringLiteral("surface dimensions are outside trusted limits"));
  }

  const qsizetype pixelCount =
      static_cast<qsizetype>(width) * static_cast<qsizetype>(height);
  if (pixelCount > maximumFrameBytes / bytesPerPixel) {
    return reject(
        QStringLiteral("surface allocation exceeds the trusted byte limit"));
  }
  if (offset < 0 || offset > maximumFrameBytes) {
    return reject(QStringLiteral("surface offset is outside trusted limits"));
  }

  m_surfaceSize = QSize(width, height);
  m_offset = offset;
  ++m_surfaceGeneration;
  m_frame = {};
  m_lastError.clear();
  emit frameChanged();
  emit lastErrorChanged();
  emit surfaceGenerationChanged();
  return true;
}

bool HostFrameItem::importFrameForTest(int fd, qint64 declaredLength,
                                       int declaredWidth, int declaredHeight) {
  if (!m_surfaceSize.isValid()) {
    return reject(QStringLiteral("surface is not configured"));
  }

  const qsizetype expectedLength =
      static_cast<qsizetype>(m_surfaceSize.width()) *
      static_cast<qsizetype>(m_surfaceSize.height()) * bytesPerPixel;

  if (declaredWidth != m_surfaceSize.width() ||
      declaredHeight != m_surfaceSize.height()) {
    return reject(
        QStringLiteral("worker dimensions do not match the host allocation"));
  }
  if (declaredLength != expectedLength) {
    return reject(
        QStringLiteral("worker length does not match the host allocation"));
  }
  if (fd < 0) {
    return reject(QStringLiteral("invalid frame descriptor"));
  }

  OwnedFd ownedFd(fcntl(fd, F_DUPFD_CLOEXEC, 0));
  if (ownedFd.get() < 0) {
    return reject(QStringLiteral("cannot duplicate frame descriptor: %1")
                      .arg(QString::fromLocal8Bit(std::strerror(errno))));
  }

  struct stat descriptorStat{};
  if (fstat(ownedFd.get(), &descriptorStat) != 0) {
    return reject(QStringLiteral("cannot stat frame descriptor: %1")
                      .arg(QString::fromLocal8Bit(std::strerror(errno))));
  }
  if (!S_ISREG(descriptorStat.st_mode)) {
    return reject(
        QStringLiteral("frame descriptor is not a regular memory file"));
  }
  if (m_offset > descriptorStat.st_size ||
      expectedLength > descriptorStat.st_size - m_offset) {
    return reject(
        QStringLiteral("frame payload falls outside the fixed descriptor"));
  }

  const int seals = fcntl(ownedFd.get(), F_GET_SEALS);
  constexpr int requiredSeals = F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE;
  if (seals < 0 || (seals & requiredSeals) != requiredSeals) {
    return reject(
        QStringLiteral("frame descriptor is not fixed and immutable"));
  }

  const long pageSize = sysconf(_SC_PAGESIZE);
  if (pageSize <= 0) {
    return reject(QStringLiteral("cannot determine the system page size"));
  }

  const qint64 alignedOffset = m_offset - (m_offset % pageSize);
  const qsizetype delta = static_cast<qsizetype>(m_offset - alignedOffset);
  if (expectedLength > maximumFrameBytes ||
      delta > maximumFrameBytes - expectedLength) {
    return reject(
        QStringLiteral("aligned mapping exceeds the trusted byte limit"));
  }
  const qsizetype mappingLength = delta + expectedLength;

  void *mapping = mmap(nullptr, static_cast<size_t>(mappingLength), PROT_READ,
                       MAP_SHARED, ownedFd.get(), alignedOffset);
  if (mapping == MAP_FAILED) {
    return reject(QStringLiteral("cannot map frame descriptor: %1")
                      .arg(QString::fromLocal8Bit(std::strerror(errno))));
  }

  const auto *pixels = static_cast<const uchar *>(mapping) + delta;
  const qsizetype stride =
      static_cast<qsizetype>(m_surfaceSize.width()) * bytesPerPixel;
  const QImage untrustedView(pixels, m_surfaceSize.width(),
                             m_surfaceSize.height(), stride,
                             QImage::Format_RGBA8888_Premultiplied);
  const QImage trustedCopy = untrustedView.copy();
  munmap(mapping, static_cast<size_t>(mappingLength));

  if (trustedCopy.isNull() || trustedCopy.size() != m_surfaceSize ||
      trustedCopy.sizeInBytes() != expectedLength) {
    return reject(
        QStringLiteral("copied frame failed trusted image validation"));
  }

  m_frame = trustedCopy;
  m_lastError.clear();
  emit lastErrorChanged();
  emit frameChanged();
  return true;
}

bool HostFrameItem::reject(const QString &message) {
  m_lastError = message;
  emit lastErrorChanged();
  return false;
}
