#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command python3

# oauth_login reads two files that only ever exist side by side, so the plan it
# settles on is exercised over a planted config directory: credentials for the
# token, the CLI's profile for the account it belongs to. The profile sits
# beside the directory by default and inside it when CLAUDE_CONFIG_DIR moved
# the whole config elsewhere, so the caller says which shape to plant.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

read_plan() {
  local credentials="$1" profile="$2" where="${3:-beside}"
  local dir plan
  dir=$(mktemp -d "$SANDBOX/config.XXXXXX")
  printf '%s' "$credentials" >"$dir/.credentials.json"
  if [[ -n $profile ]]; then
    if [[ $where == "inside" ]]; then
      printf '%s' "$profile" >"$dir/.claude.json"
    else
      printf '%s' "$profile" >"$dir.json"
    fi
  fi

  plan=$(COLLECTOR="$ROOT/bin/omarchy-agent-usage-claude" CLAUDE_DIR="$dir" python3 - <<'PY'
import importlib.machinery, importlib.util, os, pathlib

loader = importlib.machinery.SourceFileLoader("collector", os.environ["COLLECTOR"])
spec = importlib.util.spec_from_loader(loader.name, loader)
collector = importlib.util.module_from_spec(spec)
loader.exec_module(collector)

print(collector.oauth_login(pathlib.Path(os.environ["CLAUDE_DIR"]))[2])
PY
  )

  printf '%s' "$plan"
}

credentials='{"claudeAiOauth":{"accessToken":"token","expiresAt":1,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}'
upgraded='{"oauthAccount":{"organizationRateLimitTier":"default_claude_max_20x","userRateLimitTier":null}}'

# The tier in the credentials is the one the token was minted with. An upgraded
# account keeps it there, so the profile the CLI refreshes decides the label.
plan=$(read_plan "$credentials" "$upgraded")
[[ $plan == "Max 20x" ]] ||
  fail "Claude collector labels the plan from the refreshed profile" "$plan"
pass "Claude collector labels the plan from the refreshed profile"

# CLAUDE_CONFIG_DIR takes the profile along with the rest of the config.
plan=$(read_plan "$credentials" "$upgraded" inside)
[[ $plan == "Max 20x" ]] ||
  fail "Claude collector finds the profile inside a relocated config directory" "$plan"
pass "Claude collector finds the profile inside a relocated config directory"

# A seat with a tier of its own is limited by that tier, not by its org's.
plan=$(read_plan "$credentials" '{"oauthAccount":{"organizationRateLimitTier":"default_claude_max_20x","userRateLimitTier":"default_claude_max_5x"}}')
[[ $plan == "Max 5x" ]] ||
  fail "Claude collector prefers the seat's own tier over the organization's" "$plan"
pass "Claude collector prefers the seat's own tier over the organization's"

# Without a profile — or with one that states no tier, or a tier the label
# cannot read — the credentials are all there is, and they still answer.
for profile in '' '{}' '{"oauthAccount":{"organizationRateLimitTier":null}}' '{"oauthAccount":{"organizationRateLimitTier":"default_claude_unknown"}}'; do
  plan=$(read_plan "$credentials" "$profile")
  [[ $plan == "Max 5x" ]] ||
    fail "Claude collector falls back to the credentials when the profile names no readable tier" "$profile -> $plan"
done
pass "Claude collector falls back to the credentials when the profile names no readable tier"
