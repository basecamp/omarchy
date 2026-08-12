echo "Invite existing installs to pick a default agent"

# The invitation is installed by first-run, which existing accounts have already
# marked complete, so they would never receive it. They are also the accounts
# most likely to need it: the old getter returned opencode implicitly, so most
# have no agent recorded at all.
#
# Post-update hooks run later in this same update, so the invitation appears
# without waiting for another one. The hook decides whether to notify.
omarchy-hook-install post-update "$OMARCHY_PATH/install/user/first-run/setup-agent.hook"
