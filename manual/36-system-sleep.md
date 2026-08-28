# System sleep

Omarchy enables suspend and hibernation by default, but if you're having issues with either on your machine, you can toggle them off.

### Power profiles

On a laptop, Omarchy remembers your power profile separately for plugged in and running on battery, and switches between the two as you plug and unplug. Out of the box that means performance on AC and balanced on battery.

You can see what your machine offers with `omarchy powerprofiles list`, and set the one you want for the state you're currently in with `omarchy powerprofiles set autodetect power-saver`. To set the other state without unplugging anything, name it directly: `omarchy powerprofiles set battery power-saver`. Whatever you pick is what you'll get back the next time you're in that state.

### USB power saving

Linux lets idle USB devices power down after a couple of seconds, and Omarchy leaves that alone. It's a real saving on battery — a port held awake keeps its controller awake with it — and for most peripherals you'll never notice it happen.

Occasionally you will. A dock, a webcam, a DAC, or a wireless dongle that handles the wake badly turns up as input that lags for a beat when you come back to the machine, audio that clips the front of a sound, or a device that drops off the bus and takes its time coming back.

Fix it for the one device rather than all of them. `inxi -Jxxx` lists what's on the bus:

```
USB:
  Device-1: 3-6:2 info: Integrated_Webcam_FHD type: video driver: uvcvideo
    interfaces: 4 rev: 2.0 speed: 480 Mb/s lanes: 1 power: 500mA chip-ID: 1bcf:2ba9 class-ID: 0e02
```

The `chip-ID` is the vendor and product ID pair. Take the one belonging to the device that's misbehaving, and keep it powered with a udev rule in `/etc/udev/rules.d/99-usb-no-autosuspend.rules`:

```
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="2ba9", ATTR{power/control}="on"
```

The `99` matters. systemd ships `60-autosuspend.rules`, which sets `power/control` back to `auto` for every device its hardware database marks as safe to suspend. A rule numbered below that gets quietly undone for exactly the devices you'd want to exempt.

Then reload the rules and replug the device, or reboot:

```bash
sudo udevadm control --reload
```

To confirm it took, `grep . /sys/bus/usb/devices/*/power/control` prints each device's path beside its setting, and the one you named reads `on`.

There is a global version of this, `usbcore.autosuspend=-1` on the kernel command line, which stops every USB device from powering down. It's the blunt instrument: it spends battery on your whole USB tree to settle one peripheral, so try the rule above first.

### Toggle suspend

You toggle suspend by running `omarchy toggle suspend` from the terminal. That just reveals/hides the option under _System_ (or `Super + Esc`), and then you can see if it works consistently on your system. If not, you can hide it again with the same command.

### Toggle hibernation

You set up hibernation by running `omarchy hibernation setup` from the terminal. Hibernation creates a /swap subvolume on your boot drive the size of your physical RAM allocation, so make sure you have plenty of room to spare. On a 32GB machine, you'll always need 32GB+ free for this volume. Hibernation also requires the default Limine bootloader.

When set up, you'll see the hibernate option under _System_ (or `Super + Esc`), and then you can see if it works consistently on your system. If not, you can remove it again by running `omarchy hibernation remove`.
