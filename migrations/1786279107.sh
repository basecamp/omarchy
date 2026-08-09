echo "Add the keyboard layout widget to the bar"

# The widget is now in the default layout, sitting just right of the clock. It
# hides itself unless the active keyboard has more than one layout configured,
# so adding it to every existing bar is free: a machine on a single kb_layout
# never sees it. A bar that already carries the widget keeps it where the user
# put it.

omarchy-bar put omarchy.keyboard-layout --after omarchy.clock
