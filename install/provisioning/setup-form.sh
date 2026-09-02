# The setup form: every question Omarchy asks a human to describe their machine
# — who it is for, keyboard, account, hostname, timezone — plus the rules those
# answers are checked against. Shared by the two places that ask them: the ISO
# configurator's user step and this package's first-boot owner setup
# (omarchy-provision-owner). Sourced by both, so the copies cannot drift the way
# the keyboard list already did.
#
# Every prompt reports one of three statuses, and both callers read them the
# same way:
#
#   0    field is set, move on
#   1    Esc — unwind to the start of the form
#   130  Ctrl+C — a per-caller side channel (the installer toggles encryption,
#        and armed deferred provisioning until omarchy_prompt_computer_for took
#        that over as the first question; first-boot setup offers a reboot)
#
# gum is the reason those two are the whole vocabulary: Esc and Ctrl+C are the
# only keys any gum widget exits on, and Ctrl+C arrives as a byte in raw mode,
# so it never reaches the shell as SIGINT. Act on the status, never on a trap.
#
# Callers supply `notice <message> <seconds>` for validation feedback, and set
# the variables these prompts write: computer_for, keyboard, keyboard_label,
# username, password, password_confirmation, parent_password,
# parent_password_confirmation, full_name, email_address, hostname, timezone.

OMARCHY_FORM_BACK=1
OMARCHY_FORM_SIGNAL=130

# The English layouts lead, then everything else alphabetically. gum choose
# paginates in --height-sized pages and jumps to the page holding --selected,
# so an alphabetical English (US) landed deep enough to sit alone at the edge
# of a page of layouts nobody scanning for it reads. Up here the default and
# its variants are the first thing on screen no matter how the list grows.
OMARCHY_KEYBOARD_LAYOUTS=$'English (US)|us
English (UK)|uk
English (US, Dvorak)|dvorak
English (US, Colemak)|colemak
Azerbaijani|azerty
Belarusian|by
Belgian|be-latin1
Bulgarian|bg-cp1251
Croatian|croat
Czech|cz
Danish|dk-latin1
Dutch|nl
Estonian|et
Finnish|fi
French|fr
French (Canada)|cf
French (Switzerland)|fr_CH
Georgian|ge
German|de
German (Switzerland)|de_CH-latin1
Greek|gr
Hebrew|il
Hungarian|hu
Icelandic|is-latin1
Irish|ie
Italian|it
Japanese|jp106
Kazakh|kazakh
Kyrgyz|kyrgyz
Lao|la-latin1
Latvian|lv
Lithuanian|lt
Macedonian|mk-utf
Norwegian|no-latin1
Polish|pl
Portuguese|pt-latin1
Portuguese (Brazil)|br-abnt2
Romanian|ro
Russian|ru
Serbian|sr-latin
Slovak|sk-qwertz
Slovenian|slovene
Spanish|es
Spanish (Latin American)|la-latin1
Swedish|sv-latin1
Tajik|tj_alt-UTF8
Turkish|trq
Ukrainian|ua'

# The first question. Me and Child pick the install profile (default, child);
# Another owner defers the personal setup to the machine's first boot. Labels
# lead and values follow, like the keyboard list.
OMARCHY_COMPUTER_FOR_CHOICES=$'Me|me
Child|child
Another owner|other'

OMARCHY_USERNAME_PATTERN='^[a-z_][a-z0-9_-]*[$]?$'
OMARCHY_RESERVED_USERNAMES='^(root|bin|daemon|mail|ftp|http|nobody|dbus|systemd-coredump|systemd-network|systemd-oom|systemd-journal-remote|systemd-resolve|systemd-timesync|tss|uuidd|alpm|git|avahi|cups|cups-browsed|lp|_talkd|polkitd|rtkit|qemu|brltty|gluster|rpc|libvirt-qemu|pcscd|nvidia-persistenced|sddm)$'
OMARCHY_HOSTNAME_PATTERN='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
OMARCHY_HOSTNAME_DEFAULT='omarchy'

# Installer targets are empty, so any account is fair game; first-boot setup
# overrides this because its machine already has users.
omarchy_username_taken() { return 1; }

# `x=$(gum ...) && status=0 || status=$?` rather than a bare assignment followed
# by `status=$?`: one caller runs under `set -e`, where a cancelled prompt is a
# failing assignment that would kill the script before the status is read.

omarchy_prompt_computer_for() {
  local choice status
  choice=$(printf '%s\n' "$OMARCHY_COMPUTER_FOR_CHOICES" | cut -d'|' -f1 |
    gum choose --height 5 --selected "Me" --header "Who is this computer for?") && status=0 || status=$?
  ((status == 0)) || return $status

  computer_for=$(printf '%s\n' "$OMARCHY_COMPUTER_FOR_CHOICES" | awk -F'|' -v c="$choice" '$1==c{print $2; exit}')
}

omarchy_prompt_keyboard() {
  local choice status
  choice=$(printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | cut -d'|' -f1 |
    gum choose --height 10 --selected "English (US)" --header "Select keyboard layout") && status=0 || status=$?
  ((status == 0)) || return $status

  keyboard_label="$choice"
  keyboard=$(printf '%s\n' "$OMARCHY_KEYBOARD_LAYOUTS" | awk -F'|' -v c="$choice" '$1==c{print $2; exit}')
}

omarchy_prompt_username() {
  local status
  while true; do
    username=$(gum input --placeholder "Alphanumeric without spaces (like dhh)" --prompt.foreground="#845DF9" --prompt "Username> ") && status=0 || status=$?
    ((status == 0)) || return $status

    if [[ "$username" =~ $OMARCHY_USERNAME_PATTERN ]]; then
      if [[ "$username" =~ $OMARCHY_RESERVED_USERNAMES ]]; then
        notice "Username is reserved for system" 1
      elif omarchy_username_taken "$username"; then
        notice "That username already exists on this machine" 1
      else
        return 0
      fi
    else
      notice "Username must be alphanumeric with no spaces" 1
    fi
  done
}

# `kid` asks for a child install's login password: the same rules, but the
# placeholder no longer promises root, which the parent password owns there.
omarchy_prompt_password() {
  local mode=${1:-} status
  local label="Password> " placeholder="Used for user + root, and disk encryption when enabled"
  if [[ $mode == "kid" ]]; then
    label="Kid password> "
    placeholder="Used for login, unlocking, and disk encryption when enabled"
  fi

  while true; do
    password=$(gum input --placeholder "$placeholder" --prompt.foreground="#845DF9" --password --prompt "$label") && status=0 || status=$?
    ((status == 0)) || return $status
    password_confirmation=$(gum input --placeholder "Must match the password you just typed" --prompt.foreground="#845DF9" --password --prompt "Confirm> ") && status=0 || status=$?
    ((status == 0)) || return $status

    if [[ -n "$password" && "$password" == "$password_confirmation" ]]; then
      return 0
    elif [[ -z "$password" ]]; then
      notice "Your password can't be blank!" 1
    else
      notice "Passwords didn't match!" 1
    fi
  done
}

# The parent password on a child install: what sudo and system prompts ask for.
# Asked after the kid password so it can be checked against it — the split is
# pointless when the two are the same.
omarchy_prompt_parent_password() {
  local status
  while true; do
    parent_password=$(gum input --placeholder "Asked by sudo, updates, and installs (keep it from the kid)" --prompt.foreground="#845DF9" --password --prompt "Parent password> ") && status=0 || status=$?
    ((status == 0)) || return $status
    parent_password_confirmation=$(gum input --placeholder "Must match the parent password you just typed" --prompt.foreground="#845DF9" --password --prompt "Confirm> ") && status=0 || status=$?
    ((status == 0)) || return $status

    if [[ -z "$parent_password" ]]; then
      notice "The parent password can't be blank!" 1
    elif [[ "$parent_password" != "$parent_password_confirmation" ]]; then
      notice "Parent passwords didn't match!" 1
    elif [[ -n "${password:-}" && "$parent_password" == "$password" ]]; then
      notice "The parent password must differ from the kid password" 1
    else
      return 0
    fi
  done
}

# Both fields are skippable with Return, so an empty value is a real answer and
# only Esc/Ctrl+C end the prompt early.
omarchy_prompt_identity() {
  local status
  full_name=$(gum input --placeholder "Used for git authentication (hit return to skip)" --prompt.foreground="#845DF9" --prompt "Full name> ") && status=0 || status=$?
  ((status == 0)) || return $status
  email_address=$(gum input --placeholder "Used for git authentication (hit return to skip)" --prompt.foreground="#845DF9" --prompt "Email address> ") && status=0 || status=$?
  return $status
}

omarchy_prompt_hostname() {
  local status
  while true; do
    hostname=$(gum input --placeholder "Letters, digits, and dashes (or return for 'omarchy')" --prompt.foreground="#845DF9" --prompt "Hostname> ") && status=0 || status=$?
    ((status == 0)) || return $status

    if [[ -z $hostname ]]; then
      hostname="$OMARCHY_HOSTNAME_DEFAULT"
      return 0
    elif [[ "$hostname" =~ $OMARCHY_HOSTNAME_PATTERN ]]; then
      return 0
    else
      notice "Hostname must be 1-63 letters, digits, or dashes, and cannot start or end with a dash" 1
    fi
  done
}

# A fresh machine often hasn't joined a network yet, so the geo guess fails
# often; guard it or a `set -e` caller dies before the filter fallback.
omarchy_prompt_timezone() {
  local guess status
  guess=$(tzupdate -p 2>/dev/null) || guess=""

  if [[ -n $guess ]]; then
    timezone=$(timedatectl list-timezones | gum choose --height 10 --selected "$guess" --header "Timezone") && status=0 || status=$?
  else
    timezone=$(timedatectl list-timezones | gum filter --height 10 --header "Timezone") && status=0 || status=$?
  fi
  ((status == 0)) || return $status

  [[ -n $timezone ]] || timezone="UTC"
}
