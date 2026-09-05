#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/home"

cat >"$test_dir/bin/mise" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_LOG"
EOF
chmod +x "$test_dir/bin/mise"

export HOME="$test_dir/home"
export MISE_LOG="$test_dir/mise.log"
export PATH="$test_dir/bin:$PATH"

"$ROOT/bin/omarchy-install-dev-env" pnpm >/dev/null

if grep -Fxq 'use -g pnpm@latest' "$MISE_LOG"; then
  pass 'development environment installer installs pnpm with mise'
else
  fail 'development environment installer installs pnpm with mise'
fi

: >"$MISE_LOG"
"$ROOT/bin/omarchy-remove-dev-env" pnpm >/dev/null

if grep -Fxq 'uninstall pnpm --all' "$MISE_LOG" && grep -Fxq 'rm -g pnpm' "$MISE_LOG"; then
  pass 'development environment remover uninstalls pnpm with mise'
else
  fail 'development environment remover uninstalls pnpm with mise'
fi
