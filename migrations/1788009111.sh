echo "Temporarily remove automatic printer discovery"

# cups-browsed is the daemon that watches the network and creates print queues
# by itself. Hardening it (1787815267) took a root daemon with a predictable
# cache down to a confined service account, but a daemon that turns anything
# advertising itself on the network into a print queue is a lot of exposure for
# a convenience, so it comes out of the default install while that is reworked.
# Temporarily, and only the discovery half: CUPS itself stays, printing keeps
# working, and a printer is added by hand in Print Settings instead of
# appearing on its own.
machine_marker="${OMARCHY_CUPS_BROWSED_REMOVAL_MARKER:-/var/lib/omarchy/migrations/1788009111}"

[[ ! -e $machine_marker ]] || exit 0

# Nothing to do on a machine that never had it. Checked before any sudo so those
# runs never prompt for a password, and before the marker so no machine pays a
# password prompt for a removal it does not need.
omarchy-pkg-present cups-browsed || exit 0

# Ask pacman whether the removal is possible before touching the service. If
# something here depends on cups-browsed, the alternative is a machine whose
# discovery daemon has been stopped and whose package removal then failed --
# broken rather than removed.
if ! pacman -R --print cups-browsed >/dev/null 2>&1; then
  echo "  Something else on this machine still depends on cups-browsed, so it is staying installed."
  exit 0
fi

# Disable before removing, and this is the only window in which it works.
# pacman deletes the unit file but not the enable symlink systemd wrote under
# /etc, and once the unit is gone `systemctl disable` refuses it by name and
# leaves the symlink dangling with nothing left that can clean it. Stopping is
# part of the same step: a daemon whose executable has been unlinked keeps
# running until it is told not to. A masked or already-disabled unit reports
# not-enabled and is left alone. Doing it before the queue list is read also
# means the list cannot grow a new entry while it is being acted on.
if systemctl is-enabled --quiet cups-browsed.service 2>/dev/null; then
  sudo systemctl disable --now cups-browsed.service
elif systemctl is-active --quiet cups-browsed.service 2>/dev/null; then
  sudo systemctl stop cups-browsed.service
fi

# cups-browsed keeps the queues it generated when it stops --
# KeepGeneratedQueuesOnShutdown defaults to Yes and nothing here overrides it --
# and those queues route through its own implicitclass backend, which goes with
# the package, so none of them can print again. The idle ones are removed rather
# than left in Print Settings looking like printers; the ones with jobs on them
# are handled below. Only queues on that backend: a printer added by hand has an
# ipp:// or usb:// device and is left alone.
#
# LC_ALL=C because lpstat translates "device for", and on a German or French
# machine the untranslated pattern would match nothing and read exactly like a
# machine that had no queues to clean up. Captured rather than piped so that
# failing to reach cupsd is distinguishable from finding nothing. The name is
# matched greedily because CUPS allows a colon in a queue name but never a
# space, so the last ": implicitclass://" is the separator and an earlier colon
# belongs to the name.
if ! queue_report=$(LC_ALL=C lpstat -v 2>/dev/null); then
  echo "  Could not ask CUPS which queues discovery had created."
  echo "  Discovery is off, but cups-browsed stays installed; remove it by hand once CUPS answers."
  exit 0
fi

generated_queues=$(printf '%s\n' "$queue_report" |
  sed -n 's|^device for \(.*\): implicitclass://.*|\1|p')

unremoved=0

while IFS= read -r queue; do
  [[ -n $queue ]] || continue

  # A queue name is whatever the printer advertised, put through cups-browsed's
  # own sanitizer. `lpstat -o` takes its destination as an optional argument, so
  # a leading dash reads as the next option and a comma as a list separator, and
  # "all" is its word for every destination. The jobs on such a queue cannot be
  # asked about, so it is left alone and named. Never a reason to keep the
  # package, though: that would hand a printer that picked its own name a veto
  # over the removal.
  if [[ $queue == -* || $queue == *,* || $queue == "all" ]]; then
    echo "  Cannot safely ask about jobs on the queue named '$queue'; remove it in Print Settings."
    continue
  fi

  # Close the queue to new jobs before looking at what is on it. Otherwise a job
  # submitted between the check and the removal -- the sudo below can sit at a
  # password prompt for as long as someone takes to type it -- is cancelled by a
  # deletion that decided the queue was empty. It also stops more jobs piling
  # onto a queue that is being left behind and can no longer route them.
  if ! sudo cupsreject -r "Printer discovery has been removed from Omarchy" "$queue"; then
    echo "  Could not stop $queue accepting new jobs, so it is being left alone."
    unremoved=1
    continue
  fi

  # Removing a queue cancels the jobs on it. implicitclass needs cups-browsed
  # only to pick a destination, so a job already past that point finishes on its
  # own; one still waiting cannot, because the daemon that would route it has
  # stopped. Neither is this migration's to throw away, so the queue is left for
  # whoever owns them, and what will and will not happen is said rather than
  # implied.
  if job_report=$(LC_ALL=C lpstat -o "$queue" 2>/dev/null); then
    if [[ -n $job_report ]]; then
      echo "  $queue still has jobs and is no longer taking new ones, so it is being left alone."
      echo "  Anything already sent to the printer finishes; anything still waiting cannot be routed now."
      echo "  Cancel what is left and remove the queue in Print Settings."
      continue
    fi
  else
    echo "  Could not check for jobs on $queue, so it is being left alone."
    continue
  fi

  # A queue another administrator removed while this was running is a queue that
  # is gone, which is the outcome wanted -- not a failure worth keeping the
  # package for.
  if ! sudo lpadmin -x "$queue"; then
    if LC_ALL=C lpstat -p "$queue" >/dev/null 2>&1; then
      echo "  Could not remove the queue $queue."
      unremoved=1
    fi
  fi
done <<<"$generated_queues"

# A queue that would not delete is a CUPS that is not answering as expected, so
# the package stays rather than deleting the backend out from under it. Discovery
# is stopped either way, which is the half that mattered. omarchy-migrate records
# this migration for the user as soon as it exits zero, so this is where the
# machine stays until someone removes the package by hand -- said plainly rather
# than dressed up as a retry.
if ((unremoved)); then
  echo "  Leaving cups-browsed installed. Discovery is off; remove the package by hand once those queues are gone."
  exit 0
fi

# Raw pacman rather than omarchy-pkg-drop, which passes -n: that discards the
# files pacman has marked as backups instead of renaming them .pacsave, and
# /etc/cups/cups-browsed.conf is one of them. A removal meant to be temporary
# should leave the machine's copy of its own configuration behind. Plain -R
# rather than -Rs, so this only ever removes the one package it names: -s also
# sweeps dependencies that have become unneeded, which is nothing today but is
# a promise the dependency graph of a rolling distribution cannot keep.
# pacman's systemd hook reloads the system manager once the unit file goes.
sudo pacman -R --noconfirm cups-browsed

# Migration state is per user, so every account on this machine runs every
# migration. Without machine-wide state, an account whose first run comes after
# someone deliberately reinstalled cups-browsed would quietly take it back out
# again. This records that the machine has had its one removal.
sudo install -Dm644 /dev/null "$machine_marker"
