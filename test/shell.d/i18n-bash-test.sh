#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

helper="$ROOT/default/bash/i18n"
bash -n "$helper" || fail "default/bash/i18n parses"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/omarchy/i18n"

cat >"$tmp/omarchy/i18n/ca.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=2; plural=(n != 1);" },
      "Update now?": "Actualitzar ara?",
      "Removing %1": "Suprimint %1",
      "%1 package": ["%1 paquet", "%1 paquets"],
      "Ampersand": "A & B"
    }
  },
  "links": {}
}
JSON

cat >"$tmp/omarchy/i18n/pl.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);" },
      "%1 file": ["%1 plik", "%1 pliki", "%1 plików"]
    }
  },
  "links": {}
}
JSON

# A rule the whitelist admits but bash cannot parse. Evaluated in the
# caller's shell it would exit a set -e script before || could catch it.
cat >"$tmp/omarchy/i18n/yy.json" <<'JSON'
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=2; plural=(n ? );" },
      "%1 item": ["one", "many"]
    }
  },
  "links": {}
}
JSON

# A plural rule is evaluated with bash arithmetic, which will run a command
# substitution hidden in an array subscript. The helper must refuse it.
cat >"$tmp/omarchy/i18n/xx.json" <<JSON
{
  "version": 1,
  "catalogs": {
    "omarchy.cli": {
      "": { "plural-forms": "nplurals=2; plural=(a[\$(touch $tmp/pwned)]);" },
      "%1 item": ["one", "many"]
    }
  },
  "links": {}
}
JSON

export XDG_CACHE_HOME="$tmp"
unset LANGUAGE LC_ALL LC_MESSAGES

check() {
  local description="$1" expected="$2" actual="$3"
  if [[ $expected == "$actual" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected"$'\n'"actual:   $actual"
  fi
}

LANG=en_US.UTF-8
source "$helper"
check "English needs no cache and returns the source" "Update now?" "$(omarchy_t "Update now?")"
check "English interpolates arguments" "Removing vim" "$(omarchy_t "Removing %1" vim)"
check "English plural follows n != 1" "3 packages" "$(omarchy_tn 3 "%1 package" "%1 packages" 3)"

LANG=ca_ES.UTF-8
check "a translated string is returned" "Actualitzar ara?" "$(omarchy_t "Update now?")"
check "arguments are interpolated into the translation" "Suprimint vim" "$(omarchy_t "Removing %1" vim)"
check "a missing key falls back to the source" "Not in catalog" "$(omarchy_t "Not in catalog")"
check "plural form one" "1 paquet" "$(omarchy_tn 1 "%1 package" "%1 packages" 1)"
check "plural form other" "5 paquets" "$(omarchy_tn 5 "%1 package" "%1 packages" 5)"
check "an ampersand in a translation is literal" "A & B" "$(omarchy_t "Ampersand")"
check "%10 is not %1 followed by 0" "j a" "$(omarchy_i18n_interpolate "%10 %1" a b c d e f g h i j)"
check "an argument containing a placeholder is not re-expanded" "say %2 in 5 min" "$(omarchy_i18n_interpolate "%1 in %2 min" "say %2" 5)"
check "an inserted argument is never re-scanned, whatever the order" "say %1 a" "$(omarchy_i18n_interpolate "%2 %1" a "say %1")"
check "a bare percent and %0 are literal" "100% %0 a" "$(omarchy_i18n_interpolate "100% %0 %1" a)"
check "a non-numeric count is treated as zero" "many" "$(omarchy_tn "a[\$(touch $tmp/pwned2)]" "one" "many")"
[[ -e $tmp/pwned2 ]] && fail "a hostile count must not run commands"
pass "a hostile count does not run commands"

LANG=pl_PL.UTF-8
check "a three-form plural rule is evaluated" "5 plików" "$(omarchy_tn 5 "%1 file" "%1 files" 5)"
check "a three-form plural rule picks the middle form" "22 pliki" "$(omarchy_tn 22 "%1 file" "%1 files" 22)"

LANG=xx_XX.UTF-8
check "a hostile plural rule falls back to English behaviour" "many" "$(omarchy_tn 3 "%1 item" "%1 items")"
[[ -e $tmp/pwned ]] && fail "a hostile plural rule must not run commands"
pass "a hostile plural rule does not run commands"

LANG=yy_YY.UTF-8
out=$(set -e; source "$helper"; omarchy_tn 3 "%1 item" "%1 items"; echo "|ok")
check "a malformed plural rule does not exit a set -e caller" "many|ok" "$out"

printf 'not json' >"$tmp/omarchy/i18n/zz.json"
LANG=zz_ZZ.UTF-8
out=$(set -e; source "$helper"; omarchy_t "Update now?"; omarchy_tn 3 "%1 item" "%1 items" 3; echo "|ok")
check "a malformed cache gives English and does not exit a set -e caller" "Update now?3 items|ok" "$out"

LANG=de_DE.UTF-8
check "a locale with no cache returns the source" "Update now?" "$(omarchy_t "Update now?")"

out=$(set -eu; source "$helper"; LANG=ca_ES.UTF-8 omarchy_t "Update now?"; echo "|ok")
check "the helper survives set -eu" "Actualitzar ara?|ok" "$out"
