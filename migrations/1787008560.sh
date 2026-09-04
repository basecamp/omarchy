echo "Install the sleep hook that re-detects external displays left dark by a resume"

# A panel behind a dock can come back from suspend with the kernel still holding
# its pre-suspend "connected" state while the link underneath is down: hotplug
# interrupts raised inside the resume window are discarded, and a dock whose
# tunnel did not fully return never re-asserts HPD afterwards. The hook watches
# for the hotplug a healthy resume brings and forces a re-detect when none
# arrives. The settings package carries it for new installs; existing machines
# need the copy.

hook_source="$OMARCHY_PATH/default/systemd/system-sleep/relink-displays"
hook_target="${OMARCHY_SLEEP_HOOK_DIR:-/usr/lib/systemd/system-sleep}/relink-displays"

[[ -f $hook_source ]] || exit 0
cmp -s "$hook_source" "$hook_target" && exit 0

sudo install -Dm755 "$hook_source" "$hook_target"
