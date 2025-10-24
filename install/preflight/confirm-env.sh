# Source get-env.sh to get the get_env_vars function
source "$OMARCHY_INSTALL/preflight/get-env.sh"

# Show environment variable confirmation if custom repo/ref/skips/tmpfs are set
if [[ -n "${OMARCHY_REPO:-}" ]] || [[ -n "${OMARCHY_REF:-}" ]] || [[ -n "${OMARCHY_DISABLE_TMPFS:-}" ]] || [[ -n "${SKIP_YARU:-}" ]] || [[ -n "${SKIP_OBS:-}" ]] || [[ -n "${SKIP_PINTA:-}" ]] || [[ -n "${SKIP_GHOSTTY:-}" ]] || [[ -n "${SKIP_SIGNAL_DESKTOP_BETA:-}" ]]; then
  echo

  # Use gum style for retries, plain echo for first-time installs
  if [[ "$OMARCHY_RETRY_INSTALL" == "true" ]]; then
    gum style "Environment Variables:"
    get_env_vars | while IFS= read -r var; do
      gum style "  $var"
    done
  else
    echo "Environment Variables:"
    get_env_vars | while IFS= read -r var; do
      echo "  $var"
    done
  fi

  echo

  # Left-align for first-time installs, centered for retries
  if [[ "$OMARCHY_RETRY_INSTALL" == "true" ]]; then
    GUM_CONFIRM_PADDING="0 0 2 ${PADDING_LEFT:-0}" gum confirm "Continue and retry with these env vars?" || exit 1
  else
    GUM_CONFIRM_PADDING="0 0 2 0" gum confirm "Continue with these env vars?" < /dev/tty || exit 1
  fi
fi
