echo "Point GitHub credential helpers at a stable mise gh invocation"

# gh auth setup-git records the absolute path of the running binary. After a
# mise upgrade that path is gone, and pointing the helper at ~/.local/bin/gh
# still fails when that stub prints mise status on stdout (#7712). Rewrite
# only the github.com / gist.github.com helpers that match those bad forms.

omarchy-cmd-present git || exit 0

good='!mise exec --quiet gh -- gh auth git-credential'
# git config value-regex uses POSIX extended regex.
bad_ere='^!(.+/mise/installs/gh/.+/gh|.+/\.local/bin/gh) auth git-credential$'

fix_helper() {
  local key=$1
  git config --global --get-all "$key" 2>/dev/null | grep -qE "$bad_ere" || return 0
  git config --global --replace-all "$key" "$good" "$bad_ere"
}

fix_helper credential.https://github.com.helper
fix_helper credential.https://gist.github.com.helper
