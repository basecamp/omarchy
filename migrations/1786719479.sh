echo "Invite existing installs to install Voxtype dictation"

# The invitation is installed by first-run, which existing accounts have already
# marked complete, so they would never receive it — the same gap fixed for the
# agent-picker invitation in 1786549201.sh.
#
# Post-update hooks run later in this same update, so the invitation appears
# without waiting for another one. The hook decides whether to notify.
omarchy-hook-install post-update "$OMARCHY_PATH/install/user/first-run/install-voxtype.hook"
