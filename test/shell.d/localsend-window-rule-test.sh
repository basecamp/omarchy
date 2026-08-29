#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

rules="$ROOT/default/hypr/apps/localsend.lua"

grep -qF 'o.window("^(Share|localsend|org\\.localsend\\.localsend_app)$", { float = true, center = true })' "$rules" ||
  fail "LocalSend's Wayland app id floats and centers"
pass "LocalSend's Wayland app id floats and centers"

grep -qF 'o.window("^(localsend|org\\.localsend\\.localsend_app)$", { size = { 1100, 700 } })' "$rules" ||
  fail "LocalSend's Wayland app id gets the intended size"
pass "LocalSend's Wayland app id gets the intended size"
