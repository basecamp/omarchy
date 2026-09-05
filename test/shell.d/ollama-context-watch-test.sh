#!/bin/bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

# Drive the watcher's journal-line parser with realistic llama.cpp lines and
# check the state it keeps. write_state is stubbed so no file is written and
# the wall-clock TTFT delta stays deterministic.
ROOT="$ROOT" python3 - <<'PY'
import importlib.machinery
import importlib.util
import os
from pathlib import Path

loader = importlib.machinery.SourceFileLoader(
  "watcher", os.environ["ROOT"] + "/bin/omarchy-ollama-context-watch")
spec = importlib.util.spec_from_loader(loader.name, loader)
watcher = importlib.util.module_from_spec(spec)
loader.exec_module(watcher)

class FakeWatch(watcher.Watcher):
  def __init__(self):
    super().__init__()
    self.state["configuredMax"] = 196608
    self.state["modelLoaded"] = "qwen3.8:27b"
    self.written = 0
  def write_state(self):
    self.written += 1

w = FakeWatch()
w.request_started_at = 1000.0  # deterministic TTFT start

def phase():
  return w.state["phase"]

# Load-time facts are captured once.
w.handle_line("llama_model_load: - type  f32:  360 tensors")
w.handle_line("load_tensors: offloaded 66/66 layers to GPU")
w.handle_line("load_tensors:        CUDA0 model buffer size = 15339.44 MiB")
assert w.state["layers"] == {"offloaded": 66, "total": 66}, w.state["layers"]
assert w.state["modelBufferMiB"] == 15339.44, w.state["modelBufferMiB"]

# A request starts: the new prompt sets the absolute input position.
w.handle_line("slot   operator(): id  0 | task 108186 | new prompt, n_ctx_slot = 196608, n_keep = 4, task.n_tokens = 49469")
assert phase() == "prefill", phase()
assert w.state["contextPos"] == 49469, w.state["contextPos"]
assert w.state["contextPeak"] == 49469, w.state["contextPeak"]

# Prefill progress lines climb and feed the live ingest speed.
w.handle_line("slot   operator(): id  0 | task 108186 | prompt processing, n_tokens = 49057, progress = 0.92")
assert phase() == "prefill", phase()
assert w.state["prefillProgress"] == {"nTokens": 49057, "percent": 0.92}, w.state["prefillProgress"]
w.prev_progress = (w.state["prefillProgress"]["nTokens"], 1001.0)
w.handle_line("slot   operator(): id  0 | task 108186 | prompt processing, n_tokens = 49469, progress = 1.00")
assert w.state["livePrefillTokensPerSec"] > 0, w.state["livePrefillTokensPerSec"]

# Prompt eval done: whole-prefill average recorded, TTFT measured, and the
# truncated flag consumed from a pending truncation marker.
w.pending_truncation = {"limit": 196608, "prompt": 49469, "keep": 4, "new": 32000}
w.handle_line("slot print_timing: id  0 | task 108186 | prompt eval time =     256.56 ms /   408 tokens (    0.63 ms per token,  1590.30 tokens per second)")
assert phase() == "generating", phase()
assert w.state["lastPrefillTokensPerSec"] == 1590.30, w.state["lastPrefillTokensPerSec"]
assert w.state["ttftCount"] == 1 and w.state["ttftLastMs"] > 0, w.state["ttftCount"]
assert w.state["truncated"] is True, w.state["truncated"]

# Generation print_timing lines carry live decode speed and the growing
# absolute position (baseline + n_gen).
w.handle_line("slot print_timing: id  0 | task 108186 | n_gen =    169, tg =  55.25 t/s, tg_3s =  55.57 t/s")
assert phase() == "generating", phase()
assert w.state["liveTokensPerSec"] == 55.57, w.state["liveTokensPerSec"]
assert w.state["contextPos"] == 49469 + 169, w.state["contextPos"]
assert w.state["maxTokensPerSec"] == 55.57, w.state["maxTokensPerSec"]
w.handle_line("slot print_timing: id  0 | task 108186 | n_gen =    502, tg =  55.30 t/s, tg_3s =  52.22 t/s")
assert w.state["contextPos"] == 49469 + 502, w.state["contextPos"]

# The closing eval-time line keeps the whole-run average and drops the live one.
w.handle_line("slot print_timing: id  0 | task 108186 |        eval time =    5368.72 ms /   547 tokens (    9.83 ms per token,   101.70 tokens per second)")
assert phase() == "idle", phase()
assert w.state["lastTokensPerSec"] == 101.70, w.state["lastTokensPerSec"]
assert w.state["liveTokensPerSec"] is None, w.state["liveTokensPerSec"]

# Stop processing settles the definitive position and clears the request
# baseline. A smaller stray request on another lineage must not lower the peak.
w.handle_line("slot      release: id  0 | task 108186 | stop processing: n_tokens = 49971, truncated = 0")
assert w.state["contextPos"] == 49971, w.state["contextPos"]
assert w.state["contextPeak"] == 49971, w.state["contextPeak"]
w.handle_line("slot   operator(): id  0 | task 108423 | new prompt, n_ctx_slot = 196608, n_keep = 4, task.n_tokens = 3000")
assert w.state["contextPos"] == 3000, w.state["contextPos"]
assert w.state["contextPeak"] == 49971, w.state["contextPeak"]

# A truncation is the one event that resets both the position and the peak.
w.handle_line('llama.cpp: msg="truncating input prompt" limit=196608 prompt=49971 keep=4 new=29000')
assert w.state["truncated"] is True, w.state["truncated"]
assert w.state["contextPos"] == 29000 and w.state["contextPeak"] == 29000, (w.state["contextPos"], w.state["contextPeak"])

print("ok - watcher parses journal lines into context, speed, and TTFT state")
PY