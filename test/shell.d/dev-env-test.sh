#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home"

cat >"$test_tmp/bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_LOG"
SCRIPT

cat >"$test_tmp/bin/sudo" <<'SCRIPT'
#!/bin/bash
exit 0
SCRIPT

cat >"$test_tmp/bin/composer" <<'SCRIPT'
#!/bin/bash
echo "composer must not create a project during setup" >&2
exit 1
SCRIPT

chmod +x "$test_tmp/bin/omarchy-pkg-add" "$test_tmp/bin/sudo" "$test_tmp/bin/composer"

export HOME="$test_tmp/home"
export PATH="$test_tmp/bin:$PATH"
export TEST_LOG="$test_tmp/packages"

output=$("$ROOT/bin/omarchy-install-dev-env" yii3)

[[ $(<"$TEST_LOG") == "php composer php-sqlite xdebug" ]] ||
  fail "Yii3 setup installs the shared PHP toolchain" "$(<"$TEST_LOG")"
pass "Yii3 setup installs the shared PHP toolchain"

for command in \
  "composer create-project yiisoft/app myproject" \
  "composer create-project yiisoft/app-api my-api" \
  "composer create-project yiisoft/app-console my-console"; do
  [[ $output == *"$command"* ]] || fail "Yii3 setup shows every project template" "$command"
done
pass "Yii3 setup shows the web, API, and console project templates"

yii3_install_row=$(grep '^  "install.development.php.yii3":' "$ROOT/default/omarchy/omarchy-menu.jsonc")
[[ $yii3_install_row == *'"icon":"","label":"Yii3"'* ]] ||
  fail "Yii3 has its branded PHP install menu entry" "$yii3_install_row"
[[ $yii3_install_row == *"omarchy-install-dev-env yii3"* ]] ||
  fail "Yii3 menu entry launches its development setup" "$yii3_install_row"
[[ $yii3_install_row != *'"disabled"'* ]] ||
  fail "Yii3 setup stays available without a global installed artifact" "$yii3_install_row"
pass "Yii3 setup stays available in the PHP install menu"

if grep -q '^  "remove.development.php.yii3":' "$ROOT/default/omarchy/omarchy-menu.jsonc"; then
  fail "Yii3 does not claim to remove project-local dependencies"
fi
pass "Yii3 has no misleading removal entry"
