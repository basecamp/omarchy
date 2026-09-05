# Hardware authentication

### Fingerprint authentication

A lot of laptops come with a fingerprint sensor to do authentication. You can use this with Omarchy by running _Setup > Security > Fingerprint_ in the Omarchy menu (`Super + Space`).

That'll install the fingerprint package, collect your print, verify it, and you'll be set to go using your fingerprint to unlock from the lock screen (which you can trigger with `Super + Ctrl + L`), enter sudo mode, and authorize system prompts.

When your laptop lid is closed, the fingerprint prompt is automatically skipped, so you go straight to the password prompt instead of waiting on a sensor you can't reach. If you otherwise need to work on an external keyboard that doesn't have a sensor, just hit `CTRL + C`, when you're prompted for your fingerprint during `sudo`.

You can remove the fingerprint authentication under _Remove > Security > Fingerprint_ in the Omarchy menu.

### Face authentication

If your webcam has an infrared sensor — the kind sold for Windows Hello — you can unlock with your face by running _Setup > Security > Face_ in the Omarchy menu (`Super + Space`). The menu entry only appears when an IR camera is detected.

That'll install Howdy, capture your face, and set you up to unlock from the lock screen (`Super + Ctrl + L`), enter sudo mode, and authorize system prompts. On the lock screen the scan runs on its own while the screen is awake, so you just look at it; the screen going dark stops the camera, and moving the mouse starts it again.

Omarchy insists on an infrared camera rather than an ordinary webcam. IR sees in the dark, and a phone or a laptop screen held up to the lens doesn't render on an infrared sensor at all, so the cheapest way to fool an ordinary webcam doesn't work here.

Some of those cameras ship with their emitter switched off, and only turn it on when a vendor-specific control tells them to. Enrollment then fails with an empty frame, because nothing is lighting you. Setup will say so and point you at `linux-enable-ir-emitter`, which hunts down that control once; after that Omarchy switches the emitter on by itself whenever it needs the camera. It is worth facing away from windows while you set this up — daylight carries plenty of infrared, and a bright window behind you washes out the very frames the camera is trying to read.

Face authentication is skipped over SSH, where there's nobody in front of the camera to look at. Your password keeps working everywhere, so if the camera misses you, just type it as usual.

On OpenCV 5 you may notice a couple of lines like `[ WARN:0@0.004] global net_impl_backend.cpp:345 setPreferableTarget Targets are not supported by the new graph engine for now` every time face authentication runs. Nothing is wrong. OpenCV's new inference engine already runs on the CPU, so the request it is grumbling about was a no-op, and recognition is unaffected. The fix is already merged upstream in OpenCV and arrives with 5.1. There is nothing to configure in the meantime, and no environment variable will silence it, because the comparison runs in a process whose environment is deliberately scrubbed.

Bear in mind that a face is weaker proof than a password. Someone who looks a lot like you may get in, and so may a printed photograph of you: a print reflects the emitter's infrared much the way skin does, and Howdy doesn't check for liveness, so nothing tells the two apart. Requiring an infrared camera raises the cost of getting in; it doesn't turn your face into a second factor. Treat face unlock as a convenience, and don't set it up on a machine where someone else getting in would be a real problem.

You can remove the face authentication under _Remove > Security > Face_ in the Omarchy menu.

### Fido2 authentication

If you're using a Fido2 device, you can set it up for `sudo` authentication using _Setup > Security > Fido2_ in the Omarchy menu (`Super + Space`). It covers `sudo` and system authorization prompts, though, not unlocking your computer.

You can remove the fido2 authentication under _Remove > Security > Fido2_ in the Omarchy menu.
