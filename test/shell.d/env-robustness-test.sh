#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# OMARCHY_PATH is exported by the uwsm session environment and the interactive
# bash rc (default/bash/env-bootstrap). Exec contexts that skip the login shell
# -- sudo env_reset, systemd units, ssh exec, cron -- inherit no value. Scripts
# with `set -u` and a bare $OMARCHY_PATH dereference then crash before doing
# anything, which is how #8769 surfaced (omarchy-update-available via sudo).
#
# This test guards the class two ways:
#
#   1. Runtime: every script we have verified safe to invoke in a bare
#      environment is executed with `env -i`, no OMARCHY_PATH, and stubbed
#      system commands, and must not die on "unbound variable".
#   2. Classification sweep: every bin/omarchy-* script that references
#      OMARCHY_PATH must either carry a default guard, appear in RUN_LIST, or
#      be named in SKIP_LIST with a documented reason. A new unguarded script
#      added later cannot slip through unclassified.

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/home"

# Scripts run under env -i with a stub pacman so the channel detection falls to
# its package-backed "unknown" branch deterministically on any machine.
cat >"$tmp_dir/bin/pacman" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$tmp_dir/bin/pacman"

# Verified safe to invoke with no arguments in a bare environment: the first
# three exit through their usage gates, the last two are read-only and must
# reach their own answer instead of crashing on the dereference.
RUN_LIST=(
  omarchy-agent-crash
  omarchy-channel-set
  omarchy-channel-current
  omarchy-audio-tuning
)

SKIP_LIST=(
  # omarchy-update-available's unbound crash is #8769 itself; the guard and its
  # regression test are owned by PR #8771. omarchy-update-dev shares the defect
  # family and belongs with that work.
  omarchy-update-available
  omarchy-update-dev

  # No set -u, so unset expands empty instead of crashing -- the silent-degrade
  # class, deliberately out of scope for the unbound-variable sweep.
  omarchy-plugin-catalog
  omarchy-provision-first-run

  # Rewrites the agent usage files under ~/.local/state; acts on user state.
  omarchy-agent-usage-update

  # OMARCHY_PATH appears in a comment (dns) or a usage heredoc (dev-font) only.
  omarchy-dns
  omarchy-dev-font

  # Launch-class: open session-bound UI (Quickshell, compositor overlays).
  omarchy-branding-about
  omarchy-branding-screensaver
  omarchy-launch-screensaver
  omarchy-launch-shell
  omarchy-show-logo

  # Session-bound: meaningless or destructive outside a running session.
  omarchy-debug-idle
  omarchy-hyprland-toggle
  omarchy-restart-shell
  omarchy-system-sleep-monitor

  # Install-class: install or reinstall packages.
  omarchy-install-browser
  omarchy-install-chromium-copy-url
  omarchy-install-chromium-ytdlp
  omarchy-install-gaming-battlenet
  omarchy-install-terminal
  omarchy-reinstall-pkgs
  omarchy-voxtype-install

  # Interactive setup wizards.
  omarchy-setup-security-fingerprint
  omarchy-hibernation-setup

  # Overwrite user or system configuration.
  omarchy-menu-tmux-keybindings
  omarchy-refresh-applications
  omarchy-refresh-config
  omarchy-refresh-hyprland
  omarchy-refresh-limine
  omarchy-refresh-pacman
  omarchy-refresh-plymouth
  omarchy-refresh-sddm
  omarchy-shell-config
  omarchy-theme-set
  omarchy-theme-set-browser
  omarchy-theme-set-browser-policy
  omarchy-theme-set-templates
  omarchy-theme-switcher

  # Act on real system state (boot assets, snapshots, links, drivers).
  omarchy-plymouth-current
  omarchy-plymouth-list
  omarchy-plymouth-preview
  omarchy-plymouth-reset
  omarchy-plymouth-set
  omarchy-plymouth-switcher
  omarchy-snapshot
  omarchy-dev-link
  omarchy-dev-theme-preview
  omarchy-dev-unlink
  omarchy-toggle-hybrid-gpu

  # Read-only, but not part of the live-verified safe subset of the t072
  # sweep; judged statically and intentionally left out of the runtime loop.
  omarchy-theme-dir
  omarchy-theme-list
)

in_list() {
  local needle=$1 candidate
  shift
  for candidate in "$@"; do
    [[ $candidate == "$needle" ]] && return 0
  done
  return 1
}

bare_env() {
  env -i PATH="$tmp_dir/bin:/usr/bin:/bin" HOME="$tmp_dir/home" "$@"
}

# --- Runtime regressions -----------------------------------------------------

# Usage gates must keep firing before any OMARCHY_PATH dereference.
for name in "${RUN_LIST[@]:0:2}"; do
  out=$(bare_env "$ROOT/bin/$name" 2>&1) || true
  [[ $out != *"unbound variable"* ]] ||
    fail "$name no-args usage path crashes on unset OMARCHY_PATH" "$out"
done
pass "usage-gated scripts exit through their usage, not an unbound crash"

# omarchy-channel-current answers without the session environment (#8769 class).
out=$(bare_env "$ROOT/bin/omarchy-channel-current" 2>&1) || true
[[ $out != *"unbound variable"* ]] ||
  fail "omarchy-channel-current crashes on unset OMARCHY_PATH" "$out"
[[ $out == "unknown" ]] ||
  fail "omarchy-channel-current answers with the package-backed channel" "$out"
pass "omarchy-channel-current runs without OMARCHY_PATH in the environment"

# omarchy-audio-tuning status is its read-only entry point; the CLI audio group
# and omarchy-audio-output-switch reach it in exactly this bare context.
out=$(bare_env "$ROOT/bin/omarchy-audio-tuning" status 2>&1) || true
[[ $out != *"unbound variable"* ]] ||
  fail "omarchy-audio-tuning crashes on unset OMARCHY_PATH" "$out"
[[ $out == *"Installed:    no"* ]] ||
  fail "omarchy-audio-tuning status reports its tuning state" "$out"
pass "omarchy-audio-tuning status runs without OMARCHY_PATH in the environment"

# --- Classification sweep ----------------------------------------------------

# Every bin/omarchy-* script that references OMARCHY_PATH must be classified:
# guarded by a `${OMARCHY_PATH:-...}` / `${OMARCHY_PATH:=...}` default, in
# RUN_LIST (runtime-verified above), or in SKIP_LIST with a documented reason.
for script in "$ROOT"/bin/omarchy-*; do
  grep -q 'OMARCHY_PATH' "$script" || continue
  name=$(basename "$script")

  if grep -qE '\$\{OMARCHY_PATH[:-]' "$script"; then
    continue # carries a default guard already
  fi

  if in_list "$name" "${RUN_LIST[@]}"; then
    continue
  fi

  if in_list "$name" "${SKIP_LIST[@]}"; then
    continue
  fi

  fail "unclassified OMARCHY_PATH reference in $name: guard it, add it to RUN_LIST, or skip it with a documented reason"
done
pass "every OMARCHY_PATH reference in bin/ is guarded, runtime-verified, or skip-listed with a reason"
