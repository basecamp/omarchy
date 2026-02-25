# Source get-env.sh to ensure get_env_vars function is available in this subshell
source "$OMARCHY_INSTALL/preflight/get-env.sh"

# Show installation environment variables
gum log --level info "Installation Environment:"

get_env_vars | while IFS= read -r var; do
  gum log --level info "  $var"
done
