echo "Move Chromium's EULA acceptance out of unowned system state"

# Chromium 151 made the Linux EULA opt-out. Its native sentinel belongs in the
# user's data directory, alongside the rest of that profile's first-run state.
# Fresh users receive it from /etc/skel; this covers existing Quattro users.
mkdir -p "$HOME/.config/chromium"
touch "$HOME/.config/chromium/EULA Accepted"

# Omarchy 4.0.0 and 4.0.1 wrote this static seed directly into /usr. Retire only
# the exact known Omarchy values, and never remove a path another package owns
# or local state an administrator changed. Chromium now defaults its browser
# color scheme to the system setting; Omarchy's policy still supplies the hue.
chromium_prefs=/usr/lib/chromium/initial_preferences
legacy_seed_sha256=6403d77313d91ea18878f212c9f3a6a527e446ab7b0543e24c69a8520b540804
eula_seed_sha256=b9e0653f8cc4bc40a54a539760a568c4ea730f6905b2680ca795bbddcf061c01

if [[ -f $chromium_prefs && ! -L $chromium_prefs ]]; then
  if ownership_report=$(LC_ALL=C pacman -Qo "$chromium_prefs" 2>&1); then
    :
  else
    ownership_status=$?
    if (( ownership_status == 1 )) && [[ $ownership_report == "error: No package owns $chromium_prefs" ]]; then
      if ! current_seed_sha256=$(sudo sha256sum -- "$chromium_prefs" | awk '{ print $1 }'); then
        echo "Unable to hash legacy path $chromium_prefs" >&2
        exit 2
      fi

      case $current_seed_sha256 in
        "$legacy_seed_sha256"|"$eula_seed_sha256")
          sudo rm -f -- "$chromium_prefs"
          ;;
      esac
    else
      echo "Unable to verify package ownership for $chromium_prefs: $ownership_report" >&2
      exit 2
    fi
  fi
fi
