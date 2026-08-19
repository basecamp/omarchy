#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command tar
require_command curl

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
fixture="$test_tmp/fixture"
curl_log="$test_tmp/curl"
mkdir -p "$mock_bin" "$test_home/.local/bin" "$fixture/dist-package"

printf '#!/bin/bash\necho fake-cursor-agent\n' >"$fixture/dist-package/cursor-agent"
chmod +x "$fixture/dist-package/cursor-agent"
tar -czf "$fixture/agent-cli-package.tar.gz" -C "$fixture" dist-package

cat >"$fixture/install-script" <<'EOF'
#!/bin/bash
OS=linux
ARCH=x64
DOWNLOAD_URL="https://downloads.cursor.com/lab/2026.08.11-e8db854/${OS}/${ARCH}/agent-cli-package.tar.gz"
EOF

cat >"$mock_bin/uname" <<'SH'
#!/bin/bash
if [[ $1 == -m ]]; then
  echo "${OMARCHY_TEST_UNAME_M:-x86_64}"
  exit 0
fi
exec /usr/bin/uname "$@"
SH

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
out=""
url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
  -o)
    out=${args[$((i + 1))]}
    ((i++))
    ;;
  -*) ;;
  *)
    url=${args[$i]}
    ;;
  esac
done

printf '%s\n' "$url" >>"$OMARCHY_TEST_CURL_LOG"

if [[ $url == https://cursor.com/install ]]; then
  if [[ -n $out ]]; then
    cat "$OMARCHY_TEST_INSTALL_SCRIPT" >"$out"
  else
    cat "$OMARCHY_TEST_INSTALL_SCRIPT"
  fi
  exit 0
fi

if [[ $url == https://downloads.cursor.com/lab/*/linux/*/agent-cli-package.tar.gz ]]; then
  [[ ${OMARCHY_TEST_CURL_FAIL_TARBALL:-false} == "true" ]] && exit 22
  if [[ -n $out ]]; then
    cat "$OMARCHY_TEST_TARBALL" >"$out"
  else
    cat "$OMARCHY_TEST_TARBALL"
  fi
  exit 0
fi

exit 22
SH

chmod +x "$mock_bin"/*

export HOME="$test_home"
export XDG_DATA_HOME="$test_home/.local/share"
export PATH="$test_home/.local/bin:$mock_bin:$ROOT/bin:/usr/bin:/bin"
export OMARCHY_TEST_CURL_LOG="$curl_log"
export OMARCHY_TEST_INSTALL_SCRIPT="$fixture/install-script"
export OMARCHY_TEST_TARBALL="$fixture/agent-cli-package.tar.gz"

if omarchy-install-cursor-agent --check; then
  fail "Cursor installer --check fails when cursor-agent is missing"
fi
pass "Cursor installer --check fails when cursor-agent is missing"

printf '#!/bin/bash\necho official\n' >"$mock_bin/cursor-agent"
chmod +x "$mock_bin/cursor-agent"
omarchy-install-cursor-agent --check || fail "Cursor installer --check accepts a real cursor-agent on PATH"
: >"$curl_log"
omarchy-install-cursor-agent
[[ ! -s $curl_log ]] || fail "Cursor installer does not download when cursor-agent is already on PATH"
pass "Cursor installer reuses a cursor-agent already on PATH"
rm -f "$mock_bin/cursor-agent"

printf '#!/bin/bash\nmise use -g --quiet "asdf:icholy/asdf-cursor-agent" || exit 1\n' >"$test_home/.local/bin/cursor-agent"
chmod +x "$test_home/.local/bin/cursor-agent"
if omarchy-install-cursor-agent --check; then
  fail "Cursor installer --check rejects the unofficial asdf stub"
fi
: >"$curl_log"
omarchy-install-cursor-agent
[[ -L $test_home/.local/bin/cursor-agent ]] || fail "Cursor installer replaces the asdf stub with a symlink"
[[ ! -e $test_home/.local/bin/agent ]] || fail "Cursor installer does not create an agent symlink"
[[ $($test_home/.local/bin/cursor-agent) == "fake-cursor-agent" ]] ||
  fail "Cursor installer links the extracted cursor-agent binary"
mapfile -t curl_urls <"$curl_log"
[[ ${curl_urls[0]} == "https://cursor.com/install" ]] || fail "Cursor installer reads the official version from cursor.com/install"
[[ ${curl_urls[1]} == "https://downloads.cursor.com/lab/2026.08.11-e8db854/linux/x64/agent-cli-package.tar.gz" ]] ||
  fail "Cursor installer downloads the official linux tarball"
[[ -x $test_home/.local/share/cursor-agent/versions/2026.08.11-e8db854/cursor-agent ]] ||
  fail "Cursor installer extracts the CLI into the official versions directory"
pass "Cursor installer fetches Cursor's official linux tarball as cursor-agent"

rm -rf "$test_home/.local/share/cursor-agent" "$test_home/.local/bin/cursor-agent"
: >"$curl_log"
OMARCHY_TEST_UNAME_M=aarch64 omarchy-install-cursor-agent
mapfile -t curl_urls <"$curl_log"
[[ ${curl_urls[-1]} == "https://downloads.cursor.com/lab/2026.08.11-e8db854/linux/arm64/agent-cli-package.tar.gz" ]] ||
  fail "Cursor installer maps aarch64 to Cursor's arm64 tarball"
pass "Cursor installer maps aarch64 to Cursor's arm64 tarball"

rm -rf "$test_home/.local/share/cursor-agent" "$test_home/.local/bin/cursor-agent"
if OMARCHY_TEST_CURL_FAIL_TARBALL=true omarchy-install-cursor-agent >/dev/null 2>&1; then
  fail "Cursor installer reports a failed tarball download"
fi
[[ ! -e $test_home/.local/bin/cursor-agent ]] || fail "failed Cursor download leaves PATH unchanged"
pass "Cursor installer reports a failed tarball download"

if omarchy-install-cursor-agent --please >/dev/null 2>&1; then
  fail "Cursor installer rejects unknown options"
fi
pass "Cursor installer rejects unknown options"
