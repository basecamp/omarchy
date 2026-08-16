echo "Re-run the T2 defaults migration that a broken hardware check skipped"

# The T2 check in 1785944594 piped lspci into grep -q, which can exit 141 under
# the runner's pipefail when grep quits at the first match and lspci catches
# SIGPIPE. That marked the migration applied on the very hardware it targeted.
# The original is idempotent, so re-running it is safe everywhere.
source "$OMARCHY_PATH/migrations/1785944594.sh"
