echo "Take ownership of the FIDO2 authfile so it cannot be rewritten without root"

authfile="/etc/fido2/fido2"

# omarchy-migrate records this migration as complete whenever it exits zero, so
# a line printed here scrolls past once in the update terminal and is never
# shown again. The states below cannot be repaired without deciding what to do
# with a file we do not own, and they are exactly the ones where the authfile
# may already be under someone else's control, so say so where it outlives the
# scrollback as well.
report_unrepairable() {
  echo "  $1"
  echo "  $2"
  omarchy-notification-send -u critical -g  "FIDO2 authfile needs attention" "$1 $2" || true
}

# Nothing to repair on any machine that never set FIDO2 up, which is almost all
# of them. Checked before any sudo so those machines never see a password
# prompt. -L as well as -e: a dangling symlink is invisible to -e.
if [[ ! -L $authfile && ! -e $authfile ]]; then
  # Absence and "cannot look" are the same answer to the tests above. The old
  # setup created /etc/fido2 with `sudo mkdir -p`, which took the union of the
  # caller's umask and sudoers' 0022, so anyone registering under `umask 077`
  # left it mode 0700 with the user-owned authfile still inside. Escalate for
  # that case alone -- a machine that never set FIDO2 up has no directory here
  # and still reaches exit 0 without a password prompt. Not through a symlink:
  # chmod would act on whatever it points at.
  authdir=${authfile%/*}

  if [[ -L $authdir || ! -d $authdir || -x $authdir ]]; then
    exit 0
  fi

  # Ask root whether a registration is behind it before touching the directory
  # itself. An aborted setup that left an empty 0700 directory, or one an
  # administrator deliberately keeps private, must not have its mode widened
  # and its group and special bits discarded for a repair it does not need.
  if ! sudo test -e "$authfile" && ! sudo test -L "$authfile"; then
    exit 0
  fi

  sudo chmod 755 "$authdir"
fi

# The old privileged move could install a symlink here if its fixed staging path
# was redirected. Reported, not repaired: chown follows symlinks and would take
# ownership of the target instead, and removing it would strip sudo and polkit
# from anyone whose only credential is the token.
if [[ -L $authfile ]]; then
  report_unrepairable "$authfile is a symlink, not a regular file." \
    "Leaving it alone. If you did not create it, remove it and re-run Setup > Security > Fido2."
  exit 0
fi

# A directory or a device here is no more ours to rewrite than a symlink is,
# and changing a directory's mode would alter an object we do not own.
if [[ ! -f $authfile ]]; then
  report_unrepairable "$authfile is not a regular file." \
    "Leaving it alone. Remove it and re-run Setup > Security > Fido2."
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
