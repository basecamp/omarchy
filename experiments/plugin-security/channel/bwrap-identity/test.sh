#!/bin/bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

cmake -S "$root_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Debug
cmake --build "$build_dir"

output=$(timeout 15 "$build_dir/plugin-bwrap-identity-spike")
collision_output=$(timeout 15 "$build_dir/plugin-bwrap-identity-spike" --occupied-reserved)
closed_stdin_output=$(timeout 15 "$build_dir/plugin-bwrap-identity-spike" --closed-stdin)
timeout 15 "$build_dir/plugin-bwrap-identity-spike" --closed-stdout
closed_stderr_output=$(timeout 15 "$build_dir/plugin-bwrap-identity-spike" --closed-stderr)
[[ $output == *"pidfd_exit=readable"* ]]
[[ $output == *"inner_pid=1"* ]]
[[ $output == *"inner_uid=0"* ]]
[[ $output == *"unexpected_fds=0"* ]]
[[ $output == *"standard_fd_aliases=0"* ]]
[[ $output == *"control_fd=3"* ]]
[[ $output == *"broker_fd=4"* ]]
[[ $output == *"render_fd=5"* ]]
[[ $output == *"role_substitution=denied"* ]]
[[ $output == *"descendant_sender=denied"* ]]
[[ $output == *"post_exit_holder=contained"* ]]
[[ $output == *"invalid_pidfd=denied"* ]]
[[ $output == *"pre_pidfd_guard=bounded"* ]]
[[ $collision_output == *"reserved_fd_collision=denied"* ]]
[[ $closed_stdin_output == *"standard_fd_aliases=0"* ]]
[[ $closed_stderr_output == *"standard_fd_aliases=0"* ]]

reported_pid=$(sed -n 's/.*reported_outer_worker_pid=\([0-9]\+\).*/\1/p' <<<"$output")
scm_pid=$(sed -n 's/.*scm_pid=\([0-9]\+\).*/\1/p' <<<"$output")
[[ -n $reported_pid && $reported_pid == "$scm_pid" ]]

timeout 90 ctest --test-dir "$build_dir" --output-on-failure

printf '%s\n' "$output"
printf '%s\n' "$collision_output"
printf '%s\n' "$closed_stdin_output"
printf '%s\n' "$closed_stderr_output"
echo "bwrap identity spike: PASS"
