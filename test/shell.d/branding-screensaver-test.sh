#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
home_dir="$tmp_dir/home"
branding_dir="$home_dir/.config/omarchy/branding"
cache_dir="$tmp_dir/cache"
mkdir -p "$stub_bin" "$branding_dir"

cat >"$stub_bin/python" <<'SH'
#!/bin/bash

if [[ $1 == "-c" ]]; then
  printf '%s\n' "test-pyfiglet-version"
elif [[ ${1##*/} == "render_text.py" ]]; then
  printf '%s\n' "$@" >"$OMARCHY_TEST_PYTHON_ARGS.text"
  [[ ${OMARCHY_TEST_FAIL_FIGLET:-false} == "true" ]] && exit 1
  printf 'rendered with %s: %s\n' "$3" "$2"
else
  printf '%s\n' "$@" >"$OMARCHY_TEST_PYTHON_ARGS.previews"
  mkdir -p "$3"
  touch "$3/STANDARD.svg" "$3/BANNER.svg"
fi
SH

cat >"$stub_bin/omarchy-menu-input" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_INPUT_ARGS"
[[ ${OMARCHY_TEST_CANCEL_INPUT:-false} == "true" ]] && exit 1
printf '%s\n' "Hello Omarchy"
SH

cat >"$stub_bin/omarchy-menu-images" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_SELECT_ARGS"
[[ ${OMARCHY_TEST_CANCEL_SELECT:-false} == "true" ]] && exit 1
printf '%s\n' "STANDARD"
SH

cat >"$stub_bin/omarchy-launch-screensaver" <<'SH'
#!/bin/bash

printf '%s\n' "$@" >"$OMARCHY_TEST_LAUNCH_ARGS"
SH

chmod +x "$stub_bin"/*

export HOME="$home_dir"
export PATH="$stub_bin:$PATH"
export XDG_CACHE_HOME="$cache_dir"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_INPUT_ARGS="$tmp_dir/input-args"
export OMARCHY_TEST_PYTHON_ARGS="$tmp_dir/python-args"
export OMARCHY_TEST_SELECT_ARGS="$tmp_dir/select-args"
export OMARCHY_TEST_LAUNCH_ARGS="$tmp_dir/launch-args"

screensaver_path="$branding_dir/screensaver.txt"
printf '%s\n' "old screensaver" >"$screensaver_path"

"$ROOT/bin/omarchy-branding-screensaver" figlet

expected_input_args="$tmp_dir/expected-input-args"
printf '%s\n' "Screensaver text" "--width" "520" "--multiline" >"$expected_input_args"
cmp -s "$OMARCHY_TEST_INPUT_ARGS" "$expected_input_args" ||
  fail "Figlet screensaver prompts for multiline text"
pass "Figlet screensaver prompts for multiline text"

catalog_path="$ROOT/default/figlet/taag-fonts.tsv"
renderer_path="$ROOT/default/figlet/render-previews.py"
text_renderer_path="$ROOT/default/figlet/render_text.py"
[[ $(wc -l <"$catalog_path") == 35 && ! -d $ROOT/default/figlet/fonts ]] ||
  fail "Figlet screensaver uses the installed PyFiglet catalog"
pass "Figlet screensaver uses the installed PyFiglet catalog"

preview_cache_key=$(
  {
    printf '%s' "Hello Omarchy"
    printf '%s\n' "test-pyfiglet-version"
    sha256sum "$catalog_path" "$renderer_path" "$text_renderer_path"
  } | sha256sum | cut -d ' ' -f 1
)
preview_dir="$cache_dir/omarchy/figlet-selector/previews/$preview_cache_key"

expected_python_args="$tmp_dir/expected-python-args"
printf '%s\n' "$renderer_path" "Hello Omarchy" "$preview_dir" "$catalog_path" >"$expected_python_args"
cmp -s "$OMARCHY_TEST_PYTHON_ARGS.previews" "$expected_python_args" ||
  fail "Figlet screensaver renders all previews before selection"
pass "Figlet screensaver renders all previews before selection"

expected_select_args="$tmp_dir/expected-select-args"
printf '%s\n' \
  "--selected" "$preview_dir/STANDARD.svg" \
  "--print-name" "--no-thumbnails" "--fit" "$preview_dir" >"$expected_select_args"
cmp -s "$OMARCHY_TEST_SELECT_ARGS" "$expected_select_args" ||
  fail "Figlet screensaver opens fitted previews in the image selector"
pass "Figlet screensaver opens fitted previews in the image selector"

[[ -f $preview_dir/.complete ]] || fail "Figlet screensaver caches completed previews"
pass "Figlet screensaver caches completed previews"

expected_text_renderer_args="$tmp_dir/expected-text-renderer-args"
printf '%s\n' "$text_renderer_path" "Hello Omarchy" "standard" >"$expected_text_renderer_args"
cmp -s "$OMARCHY_TEST_PYTHON_ARGS.text" "$expected_text_renderer_args" ||
  fail "Figlet screensaver renders the selected font"
pass "Figlet screensaver renders the selected font"

[[ $(cat "$screensaver_path") == "rendered with standard: Hello Omarchy" ]] ||
  fail "Figlet screensaver saves rendered branding"
pass "Figlet screensaver saves rendered branding"
[[ $(cat "$OMARCHY_TEST_LAUNCH_ARGS") == "force" ]] ||
  fail "Figlet screensaver previews generated branding"
pass "Figlet screensaver previews generated branding"

rm -f "$OMARCHY_TEST_PYTHON_ARGS.previews" "$OMARCHY_TEST_PYTHON_ARGS.text"
"$ROOT/bin/omarchy-branding-screensaver" figlet
[[ ! -e $OMARCHY_TEST_PYTHON_ARGS.previews && -e $OMARCHY_TEST_PYTHON_ARGS.text ]] ||
  fail "Figlet screensaver reuses completed previews"
pass "Figlet screensaver reuses completed previews"

printf '%s\n' "keep input cancellation" >"$screensaver_path"
rm -f "$OMARCHY_TEST_SELECT_ARGS" "$OMARCHY_TEST_LAUNCH_ARGS"
OMARCHY_TEST_CANCEL_INPUT=true "$ROOT/bin/omarchy-branding-screensaver" figlet
[[ $(cat "$screensaver_path") == "keep input cancellation" ]] ||
  fail "Cancelling text input preserves screensaver branding"
[[ ! -e $OMARCHY_TEST_SELECT_ARGS && ! -e $OMARCHY_TEST_LAUNCH_ARGS ]] ||
  fail "Cancelling text input stops before selection"
pass "Cancelling text input preserves screensaver branding"

printf '%s\n' "keep font cancellation" >"$screensaver_path"
rm -f "$OMARCHY_TEST_LAUNCH_ARGS"
OMARCHY_TEST_CANCEL_SELECT=true "$ROOT/bin/omarchy-branding-screensaver" figlet
[[ $(cat "$screensaver_path") == "keep font cancellation" ]] ||
  fail "Cancelling font selection preserves screensaver branding"
[[ ! -e $OMARCHY_TEST_LAUNCH_ARGS ]] ||
  fail "Cancelling font selection does not preview a screensaver"
pass "Cancelling font selection preserves screensaver branding"

printf '%s\n' "keep failed rendering" >"$screensaver_path"
rm -f "$OMARCHY_TEST_LAUNCH_ARGS"
if OMARCHY_TEST_FAIL_FIGLET=true "$ROOT/bin/omarchy-branding-screensaver" figlet; then
  fail "A failed Figlet render reports failure"
fi
[[ $(cat "$screensaver_path") == "keep failed rendering" ]] ||
  fail "A failed Figlet render preserves screensaver branding"
if compgen -G "$screensaver_path.*" >/dev/null; then
  fail "A failed Figlet render cleans up its temporary file"
fi
[[ ! -e $OMARCHY_TEST_LAUNCH_ARGS ]] ||
  fail "A failed Figlet render does not preview a screensaver"
pass "A failed Figlet render preserves screensaver branding"
