#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_home=$(mktemp -d)
test_bin=$(mktemp -d)
test_omarchy_path=$(mktemp -d)
log_file=$(mktemp)
confirm_queue=$(mktemp)

cleanup() {
  rm -rf "$test_home" "$test_bin" "$test_omarchy_path"
  rm -f "$log_file" "$confirm_queue"
}
trap cleanup EXIT

mkdir -p "$test_omarchy_path/default/voxtype"
echo "# stub config" >"$test_omarchy_path/default/voxtype/config.toml"

# gum answers confirm prompts in order from confirm_queue (one "yes"/"no" per
# line), and no-ops for every other subcommand (style, etc.).
cat >"$test_bin/gum" <<'EOF'
#!/bin/bash
if [[ $1 == "confirm" ]]; then
  echo "confirm:$2" >>"$TEST_LOG"
  answer=$(head -n1 "$CONFIRM_QUEUE")
  sed -i '1d' "$CONFIRM_QUEUE"
  [[ $answer == "yes" ]]
  exit $?
fi
exit 0
EOF
chmod +x "$test_bin/gum"

for cmd in omarchy-pkg-add omarchy-pkg-aur-add omarchy-pkg-drop omarchy-restart-shell omarchy-notification-send omarchy-voxtype-remove; do
  cat >"$test_bin/$cmd" <<EOF
#!/bin/bash
echo "$cmd:\$*" >>"\$TEST_LOG"
EOF
  chmod +x "$test_bin/$cmd"
done

cat >"$test_bin/hyprctl" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$test_bin/hyprctl"

cat >"$test_bin/omarchy-hw-vulkan" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$test_bin/omarchy-hw-vulkan"

cat >"$test_bin/omarchy-pkg-aur-accessible" <<'EOF'
#!/bin/bash
exit "${AUR_ACCESSIBLE:-0}"
EOF
chmod +x "$test_bin/omarchy-pkg-aur-accessible"

# The installer branches its copy on the machine type, so both branches have to
# be reachable from an x86_64 test host.
cat >"$test_bin/uname" <<'EOF'
#!/bin/bash
if [[ $1 == "-m" ]]; then
  echo "${TEST_UNAME_M:-x86_64}"
else
  exec /usr/bin/uname "$@"
fi
EOF
chmod +x "$test_bin/uname"

write_hw_x86_64_v3() {
  cat >"$test_bin/omarchy-hw-x86-64-v3" <<EOF
#!/bin/bash
exit $1
EOF
  chmod +x "$test_bin/omarchy-hw-x86-64-v3"
}

write_voxtype_stub() {
  local setup_exit="${1:-0}"
  cat >"$test_bin/voxtype" <<EOF
#!/bin/bash
echo "voxtype:\$*" >>"\$TEST_LOG"
if [[ \$1 == "setup" && \$2 == "--download" ]]; then
  exit $setup_exit
fi
exit 0
EOF
  chmod +x "$test_bin/voxtype"
}

run_install() {
  local answers="$1"
  : >"$log_file"
  printf '%s\n' $answers >"$confirm_queue"
  HOME="$test_home" OMARCHY_PATH="$test_omarchy_path" PATH="$test_bin:$ROOT/bin:$PATH" \
    TEST_LOG="$log_file" CONFIRM_QUEUE="$confirm_queue" AUR_ACCESSIBLE="${2:-0}" \
    TEST_UNAME_M="${3:-x86_64}" \
    bash "$ROOT/bin/omarchy-voxtype-install"
}

# A CPU with the x86-64-v3 baseline installs the prebuilt binary as before.
write_hw_x86_64_v3 0
write_voxtype_stub 0
run_install "yes"
grep -qx 'omarchy-pkg-add:voxtype-bin' "$log_file" || fail "v3-capable CPU installs voxtype-bin"
grep -q '^omarchy-notification-send:' "$log_file" || fail "v3-capable CPU install sends the ready notification"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "v3-capable CPU install does not touch the AUR"
grep -q '^omarchy-pkg-drop:' "$log_file" && fail "v3-capable CPU install does not drop anything"

# A CPU missing the baseline, with the user declining the source build,
# installs nothing.
write_hw_x86_64_v3 1
run_install "yes no"
grep -q '^omarchy-pkg-add:voxtype-bin' "$log_file" && fail "declining the source build does not install the prebuilt binary"
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "declining the source build does not touch the AUR"

# A CPU missing the baseline, with the user accepting the source build,
# installs the AUR voxtype package instead of voxtype-bin.
write_hw_x86_64_v3 1
write_voxtype_stub 0
run_install "yes yes" 0
grep -qx 'omarchy-pkg-aur-add:aur/voxtype' "$log_file" || fail "accepting the source build installs voxtype via the AUR"
grep -q '^omarchy-pkg-add:voxtype-bin' "$log_file" && fail "accepting the source build does not install voxtype-bin"
# voxtype-bin conflicts with voxtype, so it has to go before the build's output
# can be installed over it.
drop_line=$(grep -n '^omarchy-pkg-drop:voxtype-bin$' "$log_file" | cut -d: -f1)
aur_line=$(grep -n '^omarchy-pkg-aur-add:aur/voxtype$' "$log_file" | cut -d: -f1)
if [[ -z $drop_line ]] || (( drop_line > aur_line )); then
  fail "the conflicting prebuilt binary is dropped before the source build installs"
fi

# If the AUR is unreachable, the source-build offer fails cleanly.
write_hw_x86_64_v3 1
run_install "yes yes" 1
grep -q '^omarchy-pkg-aur-add:' "$log_file" && fail "an unreachable AUR does not attempt the source install"

# On a non-x86_64 machine nothing is missing and the source build is native, so
# neither message may leak into the other architecture's branch.
write_hw_x86_64_v3 1
run_install "yes no" 0 x86_64
grep -qxF 'confirm:Build Voxtype from source instead? This can take 20+ minutes and may result in noticeably slower dictation on this CPU.' "$log_file" ||
  fail "an x86_64 CPU missing the baseline is warned the source build may be slower"

run_install "yes no" 0 aarch64
grep -qxF 'confirm:Build Voxtype from source instead? This can take 20+ minutes.' "$log_file" ||
  fail "a non-x86_64 machine is not warned about a slowdown that would not happen"

# A failure partway through setup rolls back via omarchy-voxtype-remove
# instead of leaving a half-installed package behind.
write_hw_x86_64_v3 0
write_voxtype_stub 1
run_install "yes"
grep -q '^omarchy-voxtype-remove:' "$log_file" || fail "a failed setup step triggers a rollback"

pass "Voxtype install gates on CPU capability and rolls back on failure"
