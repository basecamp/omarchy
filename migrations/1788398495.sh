echo "Remove leftover world-readable diagnostics files from /tmp"

# omarchy-debug and omarchy-upload-log used to write these under /tmp at the
# default umask (0644). The sticky bit does not stop another local account from
# reading them for as long as they remain. The scripts now stage under
# $XDG_RUNTIME_DIR / mktemp -d; drop any leftovers this user still owns.
#
# Only regular files owned by the current uid, and never through a symlink:
# /tmp is shared, so a redirected name must not make us unlink someone else's
# target. Overridable for tests.

tmp_root=${OMARCHY_LEGACY_DIAGNOSTICS_TMP:-/tmp}

remove_owned_legacy() {
  local path=$1

  # -e follows symlinks; -L catches a dangling or live symlink at the name.
  [[ -L $path ]] && return 0
  [[ -f $path ]] || return 0
  [[ -O $path ]] || return 0
  rm -f -- "$path"
}

remove_owned_legacy "$tmp_root/omarchy-debug.log"
remove_owned_legacy "$tmp_root/upload-log.txt"
remove_owned_legacy "$tmp_root/system-info.txt"
