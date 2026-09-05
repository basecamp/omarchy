#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

default_input="$ROOT/default/hypr/input.lua"
user_input="$ROOT/config/hypr/input.lua"

# The shipped touchpad defaults: physical clicks, traditional scrolling. On the
# Asahi touchpad disable_while_typing alone does not stop stray taps while
# typing, so tap-to-click is off by default and documented as a user override.
grep -Fq 'natural_scroll = false,' "$default_input" ||
  fail "shipped touchpad default uses traditional scrolling"
pass "shipped touchpad default uses traditional scrolling"

grep -Fq 'tap_to_click = false,' "$default_input" ||
  fail "shipped touchpad default turns tap-to-click off"
pass "shipped touchpad default turns tap-to-click off"

grep -Fq -- '--       natural_scroll = true,' "$user_input" ||
  fail "user override example documents natural scrolling"
pass "user override example documents natural scrolling"

grep -Fq -- '--       tap_to_click = true,' "$user_input" ||
  fail "user override example documents re-enabling tap-to-click"
pass "user override example documents re-enabling tap-to-click"
