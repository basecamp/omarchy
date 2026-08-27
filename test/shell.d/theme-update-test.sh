#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
themes="$test_tmp/themes"
started="$test_tmp/started"
mkdir -p "$mock_bin" "$started"
for number in {1..5}; do
  mkdir -p "$themes/theme-$number/.git"
done

cat >"$mock_bin/omarchy-theme-extras" <<'SH'
#!/bin/bash
printf '%s\n' "$OMARCHY_TEST_THEMES"/*
SH

cat >"$mock_bin/git" <<'SH'
#!/bin/bash

touch "$OMARCHY_TEST_STARTED/$(basename "$2")"
while [[ ! -e $OMARCHY_TEST_RELEASE ]]; do
  sleep 0.01
done
SH
chmod +x "$mock_bin/omarchy-theme-extras" "$mock_bin/git"

HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_THEMES="$themes" \
  OMARCHY_TEST_STARTED="$started" OMARCHY_TEST_RELEASE="$test_tmp/release" \
  bash "$ROOT/bin/omarchy-theme-update" >/dev/null &
updater=$!

for _ in {1..100}; do
  (( $(find "$started" -type f | wc -l) >= 4 )) && break
  sleep 0.01
done
sleep 0.1

(( $(find "$started" -type f | wc -l) == 4 )) || {
  touch "$test_tmp/release"
  wait "$updater" 2>/dev/null
  fail "theme updater runs up to four pulls in parallel"
}

touch "$test_tmp/release"
wait "$updater" || fail "theme updates finish successfully"
(( $(find "$started" -type f | wc -l) == 5 )) || fail "theme updater waits for every pull"

cat >"$mock_bin/git" <<'SH'
#!/bin/bash
[[ $(basename "$2") == "theme-1" ]]
SH
chmod +x "$mock_bin/git"

if HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_THEMES="$themes" \
  bash "$ROOT/bin/omarchy-theme-update" >/dev/null; then
  fail "theme updater reports a failed pull"
fi

pass "theme updater runs bounded parallel pulls and reports failures"
