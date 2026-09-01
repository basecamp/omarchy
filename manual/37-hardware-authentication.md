# Hardware authentication

### Fingerprint authentication

A lot of laptops come with a fingerprint sensor to do authentication. You can use this with Omarchy by running _Setup > Security > Fingerprint_ in the Omarchy menu (`Super + Space`).

That'll install the fingerprint package, collect your print, verify it, and you'll be set to go using your fingerprint to unlock from the lock screen (which you can trigger with `Super + Ctrl + L`), enter sudo mode, and authorize system prompts.

When your laptop lid is closed, the fingerprint prompt is automatically skipped, so you go straight to the password prompt instead of waiting on a sensor you can't reach. If you otherwise need to work on an external keyboard that doesn't have a sensor, just hit `CTRL + C`, when you're prompted for your fingerprint during `sudo`.

You can remove the fingerprint authentication under _Remove > Security > Fingerprint_ in the Omarchy menu.

### Face unlock

If your laptop has an infrared camera (the kind Windows Hello uses), you can unlock with your face by running _Setup > Security > Face Unlock_ in the Omarchy menu (`Super + Space`).

That'll install [howdy](https://github.com/boltgolt/howdy) from the AUR, configure the IR emitter, take a model of your face, and wire it up for the lock screen, `sudo`, and system authorization prompts.

The lock screen looks for you when you come back to it, on the first key or mouse movement after you have been away, and whenever you press `Enter` on the empty password field. Locking the screen yourself does not scan, so you are not unlocked straight back in. Typing your password still works at any time. In `sudo` and system prompts, press `Enter` on the empty password prompt to scan; a typed password skips the camera. Face unlock is skipped when the lid is closed.

You can remove face unlock under _Remove > Security > Face Unlock_ in the Omarchy menu.

### Fido2 authentication

If you're using a Fido2 device, you can set it up for `sudo` authentication using _Setup > Security > Fido2_ in the Omarchy menu (`Super + Space`). It covers `sudo` and system authorization prompts, though, not unlocking your computer.

You can remove the fido2 authentication under _Remove > Security > Fido2_ in the Omarchy menu.
