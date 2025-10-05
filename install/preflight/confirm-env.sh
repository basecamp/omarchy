# Source get-env.sh to get the get_env_vars function
source "$OMARCHY_INSTALL/preflight/get-env.sh"

# Show environment variable confirmation if custom repo/ref/skips are set
if [[ -n "${OMARCHY_REPO:-}" ]] || [[ -n "${OMARCHY_REF:-}" ]]; then
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
    gum confirm --show-help=false "Continue and retry with these env vars?" || exit 1
  else
    GUM_CONFIRM_PADDING="" gum confirm --show-help=false "Continue with these env vars?" < /dev/tty || exit 1
  fi
fi
