#!/bin/bash

set -euo pipefail

experiment_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

"$experiment_dir/native-build/run-probe"
"$experiment_dir/channel/test.sh"
"$experiment_dir/channel/bwrap-identity/test.sh"
"$experiment_dir/channel/envelope/test.sh"
"$experiment_dir/render-transport/run-test.sh"
"$experiment_dir/host-module/run-test.sh"

echo "plugin security G0 seam proofs: PASS"
