echo "Switch mise wrappers to registry shorthands"

legacy_template() {
  local package=$1 bin=$2

  printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin"
}

rewrite_wrapper() {
  local old_package=$1 new_package=$2 command=$3
  local wrapper="$HOME/.local/bin/$command"

  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || return 0
  (($(stat -c%s "$wrapper") <= 1024)) || return 0
  [[ $(<"$wrapper") == "$(legacy_template "$old_package" "$command")" ]] || return 0
  mise registry "$new_package" >/dev/null 2>&1 || return 0

  omarchy-mise-install "$new_package" "$command"
}

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  rewrite_wrapper npm:playwright playwright playwright
  rewrite_wrapper github:can1357/oh-my-pi oh-my-pi omp
  rewrite_wrapper npm:@xai-official/grok grok grok
  rewrite_wrapper npm:@kitlangton/ghui ghui ghui
  rewrite_wrapper aqua:modem-dev/hunk hunk hunk
  rewrite_wrapper github:basecamp/hey-cli hey-cli hey
  rewrite_wrapper github:OpenRouterLabs/ori-releases ori ori
fi
