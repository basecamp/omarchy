echo "Take ownership of the FIDO2 authfile so it cannot be rewritten without root"

authfile="/etc/fido2/fido2"

# Nothing to repair on any machine that never set FIDO2 up, which is almost all
# of them. Checked before any sudo so those machines never see a password
# prompt. -L as well as -e: a dangling symlink is invisible to -e.
if [[ ! -L $authfile && ! -e $authfile ]]; then
  exit 0
fi

# The old privileged move could install a symlink here if its fixed staging path
# was redirected. Reported, not repaired: chown follows symlinks and would take
# ownership of the target instead, and removing it would strip sudo and polkit
# from anyone whose only credential is the token.
if [[ -L $authfile ]]; then
  echo "  $authfile is a symlink, not a regular file."
  echo "  Leaving it alone. If you did not create it, remove it and re-run Setup > Security > Fido2."
  exit 0
fi

# A directory or a device here is no more ours to rewrite than a symlink is,
# and changing a directory's mode would alter an object we do not own.
if [[ ! -f $authfile ]]; then
  echo "  $authfile is not a regular file."
  echo "  Leaving it alone. Remove it and re-run Setup > Security > Fido2."
  exit 0
fi

# Migration state is per-user, so every account re-runs this. The file's own
# ownership is the state check: the second account finds the repair already
# done and exits without escalating.
owner=$(stat -c %U "$authfile" 2>/dev/null) || owner=""
group=$(stat -c %G "$authfile" 2>/dev/null) || group=""
mode=$(stat -c %a "$authfile" 2>/dev/null) || mode=""
if [[ $owner == "root" && $group == "root" && $mode == "644" ]]; then
  exit 0
fi

# Setup used to `mv` this in from /tmp, which carried the invoking user's
# ownership into /etc. Root ownership stops that user from rewriting their own
# PAM credential without root. Mode 644 keeps the public credential mapping
# readable when pam_u2f opens an absolute authfile as the authenticating user.
#
# Rename a fresh copy over the path rather than chowning in place. A descriptor
# opened while the file was still the user's own stays writable on that inode
# through any later chmod or chown, since permission is checked at open(2), and
# pam_u2f resolving the path would keep landing on it. Replacing the inode
# leaves that descriptor writing to a file nothing reads.
stage=""

safe_stage_path() {
  local candidate=$1
  local prefix="$authfile.new."
  local suffix

  [[ $candidate == "$prefix"* ]] || return 1
  suffix=${candidate#"$prefix"}
  [[ $suffix =~ ^[[:alnum:]]{6}$ ]]
}

cleanup_stage() {
  local status=$?

  if safe_stage_path "$stage"; then
    sudo rm -f -- "$stage" || true
  fi

  return "$status"
}

trap cleanup_stage EXIT
stage=$(sudo mktemp "$authfile.new.XXXXXX")

if ! safe_stage_path "$stage" || [[ ! -f $stage || -L $stage ]]; then
  echo "  Could not create a safe staging file beside $authfile."
  exit 1
fi

sudo install -T -m 644 -o root -g root "$authfile" "$stage"
sudo mv -Tf "$stage" "$authfile"
stage=""
trap - EXIT
