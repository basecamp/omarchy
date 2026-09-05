#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

envs="$ROOT/default/bash/envs"

editor=$(env -u EDITOR bash -c 'source "$1"; printf "%s" "$EDITOR"' bash "$envs")
[[ $editor == "omarchy-launch-editor --inline" ]] || fail "bash env provides a default editor" "actual: $editor"
pass "bash env provides a default editor"

editor=$(EDITOR=helix bash -c 'source "$1"; printf "%s" "$EDITOR"' bash "$envs")
[[ $editor == "helix" ]] || fail "bash env preserves the inherited editor" "actual: $editor"
pass "bash env preserves the inherited editor"

# sudo keeps whatever is on disk once the editor exits, so the sudo path has to
# be an editor that blocks. --inline detaches a graphical editor, which reads
# as "closed without changing anything" and loses the edit, so the Omarchy
# default routes through --sudo instead.
sudo_editor=$(env -u EDITOR -u SUDO_EDITOR bash -c 'source "$1"; printf "%s" "$SUDO_EDITOR"' bash "$envs")
[[ $sudo_editor == "omarchy-launch-editor --sudo" ]] || fail "sudo gets an editor that blocks" "actual: $sudo_editor"
pass "sudo gets an editor that blocks until the edit is done"

sudo_editor=$(env -u SUDO_EDITOR EDITOR=helix bash -c 'source "$1"; printf "%s" "$SUDO_EDITOR"' bash "$envs")
[[ $sudo_editor == "helix" ]] || fail "sudo follows an editor the user set" "actual: $sudo_editor"
pass "sudo follows an editor the user set"

sudo_editor=$(env -u EDITOR SUDO_EDITOR=nano bash -c 'source "$1"; printf "%s" "$SUDO_EDITOR"' bash "$envs")
[[ $sudo_editor == "nano" ]] || fail "an explicit sudo editor wins" "actual: $sudo_editor"
pass "an explicit sudo editor wins"
