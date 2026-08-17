# System sleep

Omarchy exposes manual suspend by default and can suspend automatically after fifteen minutes of inactivity. Hibernation becomes available after you set it up.

### Power profiles

On a laptop, Omarchy remembers your power profile separately for plugged in and running on battery, and switches between the two as you plug and unplug. Out of the box that means performance on AC and balanced on battery.

You can see what your machine offers with `omarchy powerprofiles list`, and set the one you want for the state you're currently in with `omarchy powerprofiles set autodetect power-saver`. To set the other state without unplugging anything, name it directly: `omarchy powerprofiles set battery power-saver`. Whatever you pick is what you'll get back the next time you're in that state.

### Toggle the suspend action

You toggle the manual Suspend action by running `omarchy toggle suspend` from the terminal. That reveals or hides the option under _System_ (or `Super + Esc`); it does not change automatic idle suspend.

Automatic suspend is controlled by `idle.suspend` in `~/.config/omarchy/shell.json`. The value is the number of seconds since your last activity, with a default of `900`. Stay Awake (`Super + Ctrl + I` or `omarchy toggle idle`) temporarily disables the complete idle cycle, including automatic suspend. See [toggles and idle](13-toggles-idle-screensaver.md) for the full configuration.

### Toggle hibernation

You set up hibernation by running `omarchy hibernation setup` from the terminal. Hibernation creates a /swap subvolume on your boot drive the size of your physical RAM allocation, so make sure you have plenty of room to spare. On a 32GB machine, you'll always need 32GB+ free for this volume. Hibernation also requires the default Limine bootloader.

When set up, you'll see the hibernate option under _System_ (or `Super + Esc`), and then you can see if it works consistently on your system. If not, you can remove it again by running `omarchy hibernation remove`.
