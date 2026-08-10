#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

envs="$ROOT/default/bash/envs"

# Non-login bash (SSH, herdr's remote bridge) never sources
# /etc/profile.d/locale.sh, so without this the shell runs in the C locale.
lang=$(env -u LANG bash -c 'source "$1"; printf "%s" "$LANG"' bash "$envs")
[[ -n $lang ]] || fail "bash env sets a locale when none is inherited"
pass "bash env sets a locale when none is inherited"

[[ ${lang,,} == *utf-8 || ${lang,,} == *utf8 ]] ||
  fail "bash env picks a UTF-8 locale" "actual: $lang"
pass "bash env picks a UTF-8 locale"

lang=$(LANG=en_DK.UTF-8 bash -c 'source "$1"; printf "%s" "$LANG"' bash "$envs")
[[ $lang == "en_DK.UTF-8" ]] || fail "bash env preserves the inherited locale" "actual: $lang"
pass "bash env preserves the inherited locale"

# The symptom that started this: bash only converts \u/\U escapes above 0x7f
# when the locale's charset can encode them, so default/bash/aliases prints the
# zoxide folder glyph as a literal "\U000F17A9" in the C locale.
glyph=$(env -u LANG bash -c 'source "$1"; printf "\U000F17A9"' bash "$envs")
[[ $glyph != *'\U'* ]] || fail "bash env locale renders unicode escapes" "actual: $glyph"
pass "bash env locale renders unicode escapes"
