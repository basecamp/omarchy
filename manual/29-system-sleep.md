# System sleep

Omarchy enables suspend and hibernation by default, but if you're having issues with either on your machine, you can toggle them off.

### Toggle suspend

You toggle suspend under _Setup > System Sleep > Enable/Disable Suspend_. That just reveals/hides the option under _System_ (or `Super + Esc`), and then you can see if it works consistently on your system. If not, you can turn it off again using _Setup > System Sleep > Disable Suspend_.

### Toggle hibernation

You toggle hibernation under _Setup > System Sleep > Enable/Disable Hibernation_. Hibernation creates a /swap subvolume on your boot drive the size of our physical RAM allocation, so make sure you have plenty of room to spare. On a 32GB machine, you'll always need 32GB+ free for this volume.

When enabled, you'll see the hibernate option under _System_ (or `Super + Esc`), and then you can see if it works consistently on your system. If not, you can turn it off again using _Setup > System Sleep > Disable Hibernate_.
