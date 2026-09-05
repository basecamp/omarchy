#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

python3 - "$ROOT" <<'PY'
import importlib.machinery
import importlib.util
import json
import pathlib
import sys
import tempfile
from unittest import mock


root = pathlib.Path(sys.argv[1])
script = root / "bin" / "omarchy-monitor-layout"
loader = importlib.machinery.SourceFileLoader("monitor_layout", str(script))
spec = importlib.util.spec_from_loader(loader.name, loader)
backend = importlib.util.module_from_spec(spec)
loader.exec_module(backend)

connected = [
    {
        "name": "DP-1",
        "description": "First",
        "width": 2560,
        "height": 1440,
        "modes": ["2560x1440@144.00Hz"],
    },
    {
        "name": "DP-2",
        "description": "Second",
        "width": 1920,
        "height": 1080,
        "modes": ["1920x1080@60.00Hz"],
    },
]

layout = [
    {"name": "DP-1", "mode": "2560x1440@144.00", "x": 0, "y": 0, "scale": 1, "transform": 0},
    {"name": "DP-2", "mode": "1920x1080@60.00", "x": 2560, "y": 0, "scale": 1, "transform": 0},
]

with mock.patch.object(backend, "monitors", return_value=connected):
    clean = backend.validate_layout(layout)
assert len(clean) == 2
print("ok - monitor layout accepts advertised modes on connected edges")

overlap = [dict(layout[0]), dict(layout[1], x=2000)]
with mock.patch.object(backend, "monitors", return_value=connected):
    try:
        backend.validate_layout(overlap)
    except ValueError as error:
        assert "overlap" in str(error)
    else:
        raise AssertionError("overlapping layout was accepted")
print("ok - monitor layout rejects overlaps")

legacy = "-- user settings\n\n" + backend.LEGACY_BEGIN + "\nold\n" + backend.LEGACY_END + "\n"
updated = backend.replace_block(legacy, backend.managed_block(clean))
assert backend.LEGACY_BEGIN not in updated
assert updated.count(backend.BEGIN) == 1
assert "-- user settings" in updated
print("ok - monitor layout migrates Omarview blocks without touching user settings")

payload = json.dumps(layout)
with tempfile.TemporaryDirectory() as directory:
    config = pathlib.Path(directory) / "monitors.lua"
    original = "-- exact original\n"
    config.write_text(original)
    results = [mock.Mock(stdout=""), mock.Mock(stdout="bad config"), mock.Mock(stdout="")]
    with (
        mock.patch.object(backend, "CONFIG", config),
        mock.patch.object(backend, "monitors", return_value=connected),
        mock.patch.object(backend.subprocess, "run", side_effect=results),
    ):
        try:
            backend.apply_layout(payload)
        except RuntimeError as error:
            assert "bad config" in str(error)
        else:
            raise AssertionError("invalid Hyprland configuration was accepted")
    assert config.read_text() == original
print("ok - monitor layout restores monitors.lua after a Hyprland config error")
PY
