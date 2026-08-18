#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command python3

plugin_dir="$ROOT/shell/plugins/omatask"

[[ -f "$plugin_dir/test_sampler.py" ]] || fail "omatask sampler suite exists: $plugin_dir/test_sampler.py"

# The suite parses this machine's own /proc, /sys and cgroup files rather than
# fixtures, so it also checks that the sampler still agrees with the kernel it
# is running on. It skips what the host does not expose.
if output=$(cd "$plugin_dir" && python3 test_sampler.py 2>&1); then
  pass "omatask sampler: $(tail -n 2 <<<"$output" | head -n 1)"
else
  fail "omatask sampler suite passes" "$output"
fi
