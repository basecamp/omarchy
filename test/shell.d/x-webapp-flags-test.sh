#!/bin/bash

# Super+Shift+X and the packaged X.desktop both call
# omarchy-launch-webapp with only the URL. Hybrid Intel+NVIDIA
# laptops with mixed monitor scales need extra Chromium --app
# flags injected there — not in chromium-flags.conf
# (force-device-scale-factor=1 blacks out tabbed Chromium).

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

desktop="$ROOT/applications/X.desktop"
flags="$ROOT/config/chromium-flags.conf"
launcher="$ROOT/bin/omarchy-launch-webapp"
bindings="$ROOT/default/hypr/bindings/applications.lua"

[[ -f $desktop ]] || fail "packaged X.desktop exists" "missing: $desktop"
pass "packaged X.desktop exists"

grep -E '^Exec=omarchy-launch-webapp https://x.com/' "$desktop" >/dev/null ||
  fail "X.desktop launches through omarchy-launch-webapp" "$(grep '^Exec=' "$desktop")"
pass "X.desktop launches through omarchy-launch-webapp"

grep -q 'webapp = "https://x.com/"' "$bindings" ||
  fail "Super+Shift+X launches https://x.com/ through omarchy-launch-webapp" "$(grep -n 'SHIFT + X' "$bindings")"
pass "Super+Shift+X launches https://x.com/ through omarchy-launch-webapp"

if [[ -f $flags ]]; then
  grep -q -- 'force-device-scale-factor' "$flags" &&
    fail "global chromium-flags.conf stays free of force-device-scale-factor" "$(cat "$flags")"
  grep -q -- 'disable-accelerated-video-decode' "$flags" &&
    fail "global chromium-flags.conf stays free of disable-accelerated-video-decode" "$(cat "$flags")"
  grep -q -- 'disable-gpu-memory-buffer-video-frames' "$flags" &&
    fail "global chromium-flags.conf stays free of disable-gpu-memory-buffer-video-frames" "$(cat "$flags")"
  pass "global chromium-flags.conf stays free of X-only flags"
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'EOF'
#!/bin/bash
echo chromium.desktop
EOF

cat >"$mock_bin/setsid" <<'EOF'
#!/bin/bash
exec "$@"
EOF

cat >"$mock_bin/uwsm-app" <<'EOF'
#!/bin/bash
[[ $1 == -- ]] && shift
printf '%s\n' "$@"
EOF

chmod +x "$mock_bin"/*

run_launch() {
  HOME="$test_home" PATH="$mock_bin:$PATH" bash "$launcher" "$@"
}

assert_has_flag() {
  local out=$1
  local flag=$2
  local label=$3

  printf '%s\n' "$out" | grep -Fxq -- "$flag" ||
    fail "$label" "$out"
}

assert_missing_flag() {
  local out=$1
  local flag=$2
  local label=$3

  printf '%s\n' "$out" | grep -Fxq -- "$flag" &&
    fail "$label" "$out"
}

x_out=$(run_launch "https://x.com/")
[[ $x_out == *$'\n'--app=https://x.com/$'\n'* ]] ||
  fail "x.com launch keeps --app URL" "$x_out"
assert_has_flag "$x_out" "--force-device-scale-factor=1" "x.com launch forces CSS scale 1"
assert_has_flag "$x_out" "--disable-accelerated-video-decode" "x.com launch disables broken VAAPI decode"
assert_has_flag "$x_out" "--disable-gpu-memory-buffer-video-frames" "x.com launch disables dma-buf video overlay"
pass "x.com launch injects hybrid-safe Chromium flags"

compose_out=$(run_launch "https://x.com/compose/post")
assert_has_flag "$compose_out" "--force-device-scale-factor=1" "compose/post launch forces CSS scale 1"
pass "x.com/compose/post launch injects the same flags"

twitter_out=$(run_launch "https://twitter.com/")
assert_has_flag "$twitter_out" "--disable-accelerated-video-decode" "twitter.com launch disables broken VAAPI decode"
pass "twitter.com launch injects the same flags"

yt_out=$(run_launch "https://youtube.com/")
assert_missing_flag "$yt_out" "--force-device-scale-factor=1" "YouTube launch must not force CSS scale 1"
assert_missing_flag "$yt_out" "--disable-accelerated-video-decode" "YouTube launch must not disable VAAPI"
assert_missing_flag "$yt_out" "--disable-gpu-memory-buffer-video-frames" "YouTube launch must not disable dma-buf frames"
pass "other webapps do not get the X-only flags"

passthru_out=$(run_launch "https://x.com/" --user-data-dir=/tmp/x-profile)
assert_has_flag "$passthru_out" "--user-data-dir=/tmp/x-profile" "extra args still pass through"
assert_has_flag "$passthru_out" "--force-device-scale-factor=1" "injected flags still present with extra args"
pass "extra args still pass through after injected flags"
