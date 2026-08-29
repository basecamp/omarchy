#!/bin/bash
# Snapshot store. Sourced by omarchy-local-ai; do not run.
fail() { printf 'local-ai: %s\n' "$*" >&2; return 1; }
bin_of() { [[ -x $HOME_DIR/.local/bin/$1 ]] && printf '%s\n' "$HOME_DIR/.local/bin/$1" || command -v "$1"; }
HAVE_FLOCK=0; command -v flock >/dev/null 2>&1 && HAVE_FLOCK=1
slock() { if ((HAVE_FLOCK)); then exec 9>"$ST/state.lock"; flock 9; else until mkdir "$ST/state.lockd" 2>/dev/null; do sleep 0.05; done; fi; }
sunlock() { if ((HAVE_FLOCK)); then exec 9>&-; else rmdir "$ST/state.lockd" 2>/dev/null || true; fi; }
sread() { [[ -f $SNAP ]] && cat "$SNAP" || jq -c --arg p "$REG" '.registry.path=$p' <<<"$EMPTY"; }
sw() { # sw <jq-filter> [jq-args...]
  local f=$1; shift; mkdir -p "$ST"; slock
  jq -c "$@" --arg _now "$(date +%Y-%m-%dT%H:%M:%S%z)" "($f) | .updatedAt=\$_now" <<<"$(sread)" >"$SNAP.tmp.$$"
  mv "$SNAP.tmp.$$" "$SNAP"; sunlock
}
trace() { [[ -n ${OMARCHY_AI_TRACE:-} ]] && printf '%s\n' "$1" >>"$OMARCHY_AI_TRACE"; return 0; }
setstate() { sw '.state=$s | .error=$e' --arg s "$1" --arg e "${2:-}"; trace "$1"; }
op() { sw '.operation={name:$n,recipeId:$r,percent:($p|tonumber),indeterminate:$i,detail:$d}' \
  --arg n "$1" --arg r "$2" --arg p "$3" --argjson i "$4" --arg d "$5"; }
oops() { sw '.state="error" | .error=$e | .operation.name="" | .operation.indeterminate=false' --arg e "$1"; trace error; exit 1; }
