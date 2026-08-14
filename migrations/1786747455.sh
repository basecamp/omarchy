echo "Restore conventional copy/paste bindings in foot configs seeded by Omarchy 3"

# Omarchy 3's foot.ini bound copy/paste only to Control+Insert/Shift+Insert —
# it never received the conventional Ctrl+Shift+C/V bindings the config got
# on the Omarchy 4 line. The quattro upgrade refreshes hash-verified stock
# configs, but its manifest missed the final Omarchy 3 vintage of
# foot/foot.ini, so upgraded machines kept the stale bindings in what is now
# the default terminal. Match that vintage in every state it can be in after
# the upgrade (the upgrade rewrites the legacy theme include path in place;
# migration 1785633225 then inserts multiplier=7.0) and replace the
# verified-stock file with the packaged default.

foot_config="$HOME/.config/foot/foot.ini"
packaged_config="$OMARCHY_PATH/config/foot/foot.ini"

if [[ -f $foot_config && -f $packaged_config ]]; then
  case "$(sha256sum "$foot_config" | awk '{ print $1 }')" in
    "8afc9646c61e58e67f244e50a9ce5d4a45546920511a06b47f7443a3998da602" | \
      "b4301e28e71c3e1f641bb777fa9c173ac88cf4fd56e963f42f6d6e1790240866" | \
      "01255bb4b07d72c1babc342aadfe4ad134632e288f45d24b6e7fe61a340202bd")
      cp "$packaged_config" "$foot_config"
      ;;
  esac
fi
