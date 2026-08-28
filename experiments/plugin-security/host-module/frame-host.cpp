#include <QGuiApplication>
#include <QImage>
#include <QMetaObject>
#include <QQmlComponent>
#include <QQmlEngine>

#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <memory>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

namespace {

constexpr int frameWidth = 8;
constexpr int frameHeight = 4;
constexpr qsizetype frameLength = frameWidth * frameHeight * 4;
constexpr qint64 frameOffset = 3;
constexpr qint64 maximumFrameBytes = 64 * 1024 * 1024;

int fail(const QString &message) {
  std::fprintf(stderr, "frame-smoke: %s\n", qPrintable(message));
  return 1;
}

bool invokeConfigure(QObject *object, int width, int height, qint64 offset) {
  bool result = false;
  const bool invoked = QMetaObject::invokeMethod(
      object, "configureSurface", Q_RETURN_ARG(bool, result), Q_ARG(int, width),
      Q_ARG(int, height), Q_ARG(qint64, offset));
  return invoked && result;
}

bool invokeImport(QObject *object, int fd, qint64 length, int width,
                  int height) {
  bool result = false;
  const bool invoked = QMetaObject::invokeMethod(
      object, "importFrameForTest", Q_RETURN_ARG(bool, result), Q_ARG(int, fd),
      Q_ARG(qint64, length), Q_ARG(int, width), Q_ARG(int, height));
  return invoked && result;
}

int createFrameDescriptor(qsizetype length, bool sealImmutable) {
  const int fd =
      memfd_create("omarchy-host-frame-smoke", MFD_CLOEXEC | MFD_ALLOW_SEALING);
  if (fd < 0) {
    return -1;
  }
  if (ftruncate(fd, length) != 0) {
    close(fd);
    return -1;
  }
  if (sealImmutable &&
      fcntl(fd, F_ADD_SEALS,
            F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE | F_SEAL_SEAL) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

[[noreturn]] void produceFrameAndExit(int fd, qint64 offset) {
  const size_t mappingLength =
      static_cast<size_t>(static_cast<qint64>(frameLength) + offset);
  void *mapping =
      mmap(nullptr, mappingLength, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  if (mapping == MAP_FAILED) {
    close(fd);
    _exit(1);
  }

  auto *pixels = static_cast<unsigned char *>(mapping) + offset;
  for (qsizetype index = 0; index < frameLength; index += 4) {
    pixels[index] = 0x10;
    pixels[index + 1] = static_cast<unsigned char>(0x40 + index / 4);
    pixels[index + 2] = 0x80;
    pixels[index + 3] = 0x80;
  }

  munmap(mapping, mappingLength);
  close(fd);
  _exit(0);
}

} // namespace

int main(int argc, char *argv[]) {
  if (argc != 2) {
    return fail(
        QStringLiteral("usage: omarchy-plugin-frame-smoke QML_IMPORT_ROOT"));
  }

  const int frameFd = createFrameDescriptor(frameOffset + frameLength, false);
  if (frameFd < 0) {
    return fail(QStringLiteral("cannot create fixed-size memfd"));
  }

  const pid_t producer = fork();
  if (producer < 0) {
    close(frameFd);
    return fail(QStringLiteral("cannot fork frame producer"));
  }
  if (producer == 0) {
    produceFrameAndExit(frameFd, frameOffset);
  }

  int producerStatus = 0;
  if (waitpid(producer, &producerStatus, 0) != producer ||
      !WIFEXITED(producerStatus) || WEXITSTATUS(producerStatus) != 0) {
    close(frameFd);
    return fail(QStringLiteral("frame producer did not exit successfully"));
  }
  if (fcntl(frameFd, F_ADD_SEALS,
            F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_WRITE | F_SEAL_SEAL) != 0) {
    close(frameFd);
    return fail(QStringLiteral("cannot make completed frame immutable"));
  }

  QGuiApplication application(argc, argv);
  QQmlEngine engine;
  engine.addImportPath(QString::fromLocal8Bit(argv[1]));

  QQmlComponent component(&engine);
  component.setData(R"(
import QtQuick
import Omarchy.PluginHost

HostFrameItem {}
)",
                    QUrl());
  if (component.status() != QQmlComponent::Ready) {
    close(frameFd);
    return fail(component.errorString());
  }

  std::unique_ptr<QObject> object(component.create());
  if (object == nullptr ||
      !invokeConfigure(object.get(), frameWidth, frameHeight, frameOffset)) {
    close(frameFd);
    return fail(QStringLiteral("cannot configure the trusted surface"));
  }
  if (!invokeImport(object.get(), frameFd, frameLength, frameWidth,
                    frameHeight)) {
    close(frameFd);
    return fail(QStringLiteral("cannot import the valid frame: %1")
                    .arg(object->property("lastError").toString()));
  }

  const QString validDigest = object->property("frameDigest").toString();
  const QImage validFrame = object->property("frame").value<QImage>();
  const quint64 validGeneration =
      object->property("surfaceGeneration").toULongLong();
  close(frameFd);

  if (validDigest.isEmpty() ||
      validFrame.size() != QSize(frameWidth, frameHeight) ||
      validFrame.format() != QImage::Format_RGBA8888_Premultiplied ||
      validFrame.constBits()[0] != 0x10 || validFrame.constBits()[1] != 0x40 ||
      validFrame.constBits()[2] != 0x80 || validFrame.constBits()[3] != 0x80) {
    return fail(
        QStringLiteral("trusted frame copy has unexpected metadata or pixels"));
  }

  if (invokeImport(object.get(), -1, frameLength, frameWidth + 1,
                   frameHeight) ||
      object->property("frameDigest").toString() != validDigest) {
    return fail(QStringLiteral(
        "malformed dimensions were accepted or replaced the last valid frame"));
  }
  if (invokeImport(object.get(), -1, frameLength + 4, frameWidth,
                   frameHeight) ||
      object->property("frameDigest").toString() != validDigest) {
    return fail(QStringLiteral(
        "malformed length was accepted or replaced the last valid frame"));
  }

  const int unsealedFd =
      createFrameDescriptor(frameOffset + frameLength, false);
  if (unsealedFd < 0 || invokeImport(object.get(), unsealedFd, frameLength,
                                     frameWidth, frameHeight)) {
    if (unsealedFd >= 0) {
      close(unsealedFd);
    }
    return fail(QStringLiteral("unsealed descriptor was accepted"));
  }
  close(unsealedFd);

  const int truncatedFd =
      createFrameDescriptor(frameOffset + frameLength - 1, true);
  if (truncatedFd < 0 || invokeImport(object.get(), truncatedFd, frameLength,
                                      frameWidth, frameHeight)) {
    if (truncatedFd >= 0) {
      close(truncatedFd);
    }
    return fail(QStringLiteral("truncated descriptor was accepted"));
  }
  close(truncatedFd);

  int pipeFds[2] = {-1, -1};
  if (pipe2(pipeFds, O_CLOEXEC) != 0 ||
      invokeImport(object.get(), pipeFds[0], frameLength, frameWidth,
                   frameHeight)) {
    if (pipeFds[0] >= 0) {
      close(pipeFds[0]);
      close(pipeFds[1]);
    }
    return fail(QStringLiteral("nonregular descriptor was accepted"));
  }
  close(pipeFds[0]);
  close(pipeFds[1]);

  if (invokeConfigure(object.get(), frameWidth, frameHeight, -1) ||
      invokeConfigure(object.get(), frameWidth, frameHeight,
                      maximumFrameBytes + 1) ||
      invokeConfigure(object.get(), 4097, frameHeight, frameOffset) ||
      object->property("frameDigest").toString() != validDigest ||
      object->property("surfaceGeneration").toULongLong() != validGeneration) {
    return fail(QStringLiteral(
        "invalid offset or oversize configuration changed trusted state"));
  }

  if (object->property("frameDigest").toString() != validDigest) {
    return fail(QStringLiteral("rejected descriptors replaced the last frame"));
  }

  if (!invokeConfigure(object.get(), frameWidth, frameHeight, 0) ||
      !object->property("frameDigest").toString().isEmpty() ||
      !object->property("frame").value<QImage>().isNull() ||
      object->property("surfaceGeneration").toULongLong() !=
          validGeneration + 1) {
    return fail(QStringLiteral(
        "successful surface reconfiguration retained a stale frame"));
  }

  std::fprintf(stdout,
               "frame-smoke: producer exited; copied %lld bytes; digest=%s; "
               "hostile descriptors denied; stale frame cleared on generation "
               "change\n",
               static_cast<long long>(validFrame.sizeInBytes()),
               qPrintable(validDigest));
  return 0;
}
