#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/dev-link.log"
conf_file="$test_tmp/omarchy.conf"
sudoers_file="$test_tmp/omarchy-dev-path"
dev_bin_dir="/var/lib/omarchy/dev-bin"
mkdir -p "$stub_bin" "$test_tmp/home"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$OMARCHY_DEV_LINK_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_DEV_LINK_TEST_LOG"
done
printf '\n' >>"$OMARCHY_DEV_LINK_TEST_LOG"

case "$1" in
  tee)
    cat >"$OMARCHY_DEV_LINK_TEST_CONF"
    ;;
  install)
    # The staged file is the second-to-last argument.
    cp "${@: -2:1}" "$OMARCHY_DEV_LINK_TEST_SUDOERS"
    ;;
esac
SH
chmod +x "$stub_bin/sudo"
chmod +x "$stub_bin/sudo"

# macOS /bin/realpath has no -e; GNU realpath does. Stub it for local runs.
cat >"$stub_bin/realpath" <<'SH'
#!/bin/bash
if [[ $1 == -e ]]; then
  shift
fi
path=$1
if [[ ! -e $path ]]; then
  echo "realpath: $path: No such file or directory" >&2
  exit 1
fi
# Prefer python for absolute resolution when GNU realpath is absent.
python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$path"
SH
chmod +x "$stub_bin/realpath"


cat >"$stub_bin/gum" <<'SH'
#!/bin/bash

printf 'gum' >>"$OMARCHY_DEV_LINK_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_DEV_LINK_TEST_LOG"
done
printf '\n' >>"$OMARCHY_DEV_LINK_TEST_LOG"
SH
chmod +x "$stub_bin/gum"

cat >"$stub_bin/omarchy-system-reboot" <<'SH'
#!/bin/bash

printf 'reboot\n' >>"$OMARCHY_DEV_LINK_TEST_LOG"
SH
chmod +x "$stub_bin/omarchy-system-reboot"

run_link() {
  HOME="$test_tmp/home" \
    OMARCHY_DEV_LINK_TEST_LOG="$log_file" \
    OMARCHY_DEV_LINK_TEST_CONF="$conf_file" \
    OMARCHY_DEV_LINK_TEST_SUDOERS="$sudoers_file" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-dev-link" "$@"
}

make_checkout() {
  local checkout="$test_tmp/$1"

  mkdir -p "$checkout/bin" "$checkout/default" "$checkout/shell"
  # A real omarchy-* script and a planted system-tool name in the same bin/.
  printf '#!/bin/bash\n' >"$checkout/bin/omarchy-pkg-add"
  chmod +x "$checkout/bin/omarchy-pkg-add"
  printf '#!/bin/bash\necho pwned\n' >"$checkout/bin/pacman"
  chmod +x "$checkout/bin/pacman"
  printf '%s' "$checkout"
}

checkout=$(make_checkout checkout)
checkout=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$checkout")

: >"$log_file"
: >"$sudoers_file"
run_link "$checkout" --no-reboot >"$test_tmp/link.out"

[[ $(<"$conf_file") == "export OMARCHY_PATH=\"$checkout\"" ]] ||
  fail "dev link points OMARCHY_PATH at the checkout" "$(<"$conf_file")"
pass "dev link points OMARCHY_PATH at the checkout"

# secure_path must prepend the root-owned farm, never the user-writable checkout
# itself — otherwise a planted pacman beside omarchy-pkg-add runs as root.
[[ $(<"$sudoers_file") == "Defaults secure_path=\"$dev_bin_dir:/usr/local/sbin:/usr/local/bin:/usr/bin\"" ]] ||
  fail "dev link prepends the root-owned farm to sudo's secure_path" "$(<"$sudoers_file")"
pass "dev link prepends the root-owned farm to sudo's secure_path"

grep -Eq $'^sudo\tinstall\t-Dm440\t-o\troot\t-g\troot\t[^\t]+\t/etc/sudoers\\.d/omarchy-dev-path$' "$log_file" ||
  fail "dev link installs the drop-in root-owned and read-only" "$(cat "$log_file")"
pass "dev link installs the drop-in root-owned and read-only"

grep -Eq $'^sudo\tmkdir\t-p\t/var/lib/omarchy/dev-bin$' "$log_file" ||
  fail "dev link creates the root-owned symlink farm directory" "$(cat "$log_file")"
pass "dev link creates the root-owned symlink farm directory"

grep -Eq $'^sudo\tln\t-sfn\t'"$checkout"'/bin/omarchy-pkg-add\t/var/lib/omarchy/dev-bin/omarchy-pkg-add$' "$log_file" ||
  fail "dev link publishes omarchy-* into the farm" "$(cat "$log_file")"
pass "dev link publishes omarchy-* into the farm"

if grep -Eq $'^sudo\tln\t.*bin/pacman' "$log_file"; then
  fail "dev link must not publish a planted system-tool name into the farm" "$(cat "$log_file")"
fi
pass "dev link refuses to publish a planted pacman into the farm"

visudo -cf "$sudoers_file" >/dev/null ||
  fail "dev link writes a sudoers drop-in sudo can parse" "$(<"$sudoers_file")"
pass "dev link writes a sudoers drop-in sudo can parse"

grep -F "sudo now resolves omarchy-* from $dev_bin_dir → $checkout/bin" "$test_tmp/link.out" >/dev/null ||
  fail "dev link reports the sudo change" "$(cat "$test_tmp/link.out")"
pass "dev link reports the sudo change"

if grep -Eq '^(gum|reboot)' "$log_file"; then
  fail "dev link --no-reboot skips the reboot prompt" "$(cat "$log_file")"
fi
pass "dev link --no-reboot skips the reboot prompt"

# A path sudoers would have to escape, not one the shell alone handles.
quoted_checkout=$(make_checkout 'check "out"')
quoted_checkout=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$quoted_checkout")

: >"$log_file"
: >"$sudoers_file"
run_link "$quoted_checkout" --no-reboot >/dev/null

[[ $(<"$sudoers_file") == "Defaults secure_path=\"$dev_bin_dir:/usr/local/sbin:/usr/local/bin:/usr/bin\"" ]] ||
  fail "dev link keeps the farm path even when the checkout needs escaping" "$(<"$sudoers_file")"
pass "dev link keeps the farm path even when the checkout needs escaping"

visudo -cf "$sudoers_file" >/dev/null ||
  fail "dev link escapes a checkout path for sudoers" "$(<"$sudoers_file")"
pass "dev link escapes a checkout path for sudoers"

: >"$log_file"
if run_link "$test_tmp/missing" --no-reboot >/dev/null 2>"$test_tmp/missing.err"; then
  fail "dev link rejects a path that does not exist"
fi
grep -F "Error: path does not exist: $test_tmp/missing" "$test_tmp/missing.err" >/dev/null ||
  fail "dev link explains a path that does not exist" "$(cat "$test_tmp/missing.err")"
if grep -q 'sudo' "$log_file"; then
  fail "dev link touches nothing when the path does not exist" "$(cat "$log_file")"
fi
pass "dev link rejects a path that does not exist"
