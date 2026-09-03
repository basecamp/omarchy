# QTranslator adapter proof of concept

This proof of concept checks whether Omarchy can add Qt's standard translation runtime to an unmodified Quickshell process by shipping an external C++ QML module.

It exposes one QML singleton:

```qml
import Omarchy.I18n

Component.onCompleted: Translator.load("/path/to/omarchy_ja.qm")
```

QML strings continue to use Qt's standard translation APIs:

```qml
Text { text: qsTr("Settings") }
```

## What this proves

The test launches the installed `quickshell` binary without patching or rebuilding it. It imports the external module, loads a real Japanese `.qm` catalog with `QTranslator`, and checks that an existing `qsTr()` binding changes from `&Close` to its Japanese translation.

Installing a `QTranslator` is not sufficient to update bindings that already exist. The adapter must also call `QQmlEngine::retranslate()` after installing the catalog.

## Run

Requirements:

- CMake and a C++ compiler
- Qt 6 Core and QML development files
- Quickshell
- `/usr/share/locale/ja/LC_MESSAGES/kconfig6_qt.qm` from KDE Frameworks, used only as an available real-world test catalog

```bash
cmake -S . -B build
cmake --build build
./tests/run.sh
```

Expected output includes:

```text
TEST_PASS: &Close -> 閉じる(&C)
```

The test uses Qt's offscreen platform and does not alter or restart the user's running Omarchy shell.

## Why this is not proposed as the preferred production design

The clean solution is for Quickshell to expose first-class support for loading and replacing `QTranslator` catalogs. This adapter demonstrates a fallback if upstream support is unavailable, but it would make Omarchy responsible for a native Qt binary and introduce costs that a QML-only implementation does not have:

- rebuilding and publishing the module for supported architectures;
- coordinating rebuilds with Qt ABI updates in Arch Linux;
- making shell startup resilient to a missing or incompatible native module;
- maintaining a CMake, CI, and package pipeline for a very small runtime feature;
- requiring C++ and Qt knowledge from future maintainers.

This is therefore discussion material rather than merge-ready integration. A production implementation would still need packaging, safe optional loading, TS/QM extraction and compilation, locale fallback, catalog replacement failure handling, and shell reload tests.
