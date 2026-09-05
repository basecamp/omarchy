# Screenshots & Recording

Everything you can grab off the screen hangs off the Print Screen key. One key on its own takes a picture, and the modifiers take a recording, a colour, or the text inside a region. If your keyboard doesn't have a Print Screen key at all, `Super + Ctrl + C` opens the same set as a menu.

| Hotkey | Function |
| ------ | -------- |
| `Print Screen` | Screenshot |
| `Alt + Print Screen` | Screenrecord (or stop the one that's running) |
| `Super + Print Screen` | Colour picker |
| `Super + Ctrl + Print Screen` | Extract text from a region |
| `Super + Ctrl + C` | Capture menu |
| `Super + Ctrl + .` | Transcode a picture or video |

## Screenshots

Hit `Print Screen` and Omasnap captures the focused monitor before its overlay appears, so nothing shifts under you while you aim. Drag a freeform region, or use the tabs across the top to switch between Region, Scrolling Region, Window, and Fullscreen capture. Changed your mind? Hit `Print Screen` again to dismiss Omasnap.

After you select an area, Omasnap opens its annotation editor. It can draw arrows, lines, shapes, highlights, numbered markers, text, and secure redactions; crop or cut out part of the image; OCR its text; and add a backdrop. Press `Enter` to copy and save the finished PNG, `Ctrl + C` to copy it without saving, `Ctrl + S` to save it without copying, or `P` to pin it above your windows.

Files land in `~/Pictures/Screenshots` by default, with a name such as `screenshot-2026-08-13_14-22-05-firefox.png`. Set `OMASNAP_SCREENSHOT_DIR` to use another directory — see [the FAQ](46-faq.md) for where to put session environment variables. Omasnap creates the directory when it saves the first shot.

From the terminal, `omarchy screenshot` opens the same overlay, and you can choose its starting mode: `omarchy capture screenshot region`, `windows`, `fullscreen`, or `scroll`. A second argument of `copy` or `save` bypasses the annotation editor and sends the shot straight to that destination.

### Driving the picker from the keyboard

While the selection is up, you don't have to use the mouse at all:

| Key | Function |
| --- | -------- |
| `Space` | Step through Region, Scrolling Region, and Window modes |
| `S` | Toggle scrolling-region mode |
| `Super + Arrow keys` | Move among windows in Window mode |
| `Return` | Capture the highlighted window |
| `Ctrl + A` | Capture the full focused monitor |
| `R` | Restore the last region drawn in this session |
| `Esc` | Dismiss Omasnap |

These bindings only exist while Omasnap is open, so they can't collide with anything in your own config.

## Screen recording

`Alt + Print Screen` opens _Trigger > Capture > Screenrecord_, which asks what you want on the soundtrack: no audio, desktop audio, desktop plus microphone, or desktop plus microphone plus webcam. That last one only shows up if you actually have a camera plugged in. Pick one and Omarchy's recording picker lets you drag a region or click a window or monitor.

Recording runs on gpu-screen-recorder, which encodes on the GPU at 60fps and falls back to the CPU if it has to. The result is an MP4 in `~/Videos`, named `screenrecording-2026-08-13_14-22-05.mp4`. Set `OMARCHY_SCREENRECORD_DIR` to change that — but note that unlike the screenshot directory, this one has to exist already, or the recording refuses to start.

While you're recording, a little indicator shows up in the bar. Click it to stop. You can also stop with `Alt + Print Screen` again, or with the _Stop Screenrecording_ entry under _Trigger > Capture > Screenrecord_, which only appears while something is actually recording.

Stopping does a bit of tidying before it hands you the file: the first frame gets trimmed, and if there's audio it's normalized to -14 LUFS with the PipeWire capture pop at the very start muted out. Then a notification appears with a thumbnail from the recording. Click it to play the file in mpv.

### The webcam overlay

When you record with a webcam, the camera appears as a pinned, cropped portrait window in the bottom-right corner of whatever you're recording. If it's sitting on top of something you need, resize it on the fly:

| Hotkey | Function |
| ------ | -------- |
| `Super + Alt + [` | Make the webcam overlay smaller |
| `Super + Alt + ]` | Make the webcam overlay larger |

There are three sizes — small, medium, and large — and the hotkeys step between them. Medium is the default. They're proportional to the recording, so the camera takes up the same share of the frame whether you're recording a 1080p monitor or a 6K one. And if you recorded a region rather than a whole display, the overlay anchors to that region's corner rather than the monitor's, so it stays inside the shot.

You can also call it directly with `omarchy-capture-webcam-resize small`, or `reset` to go back to medium.

## Text, QR codes, and colours

`Super + Ctrl + Print Screen` selects a region and OCRs it to the clipboard. That's covered properly in [Text Extraction & Dictation](11-text-extraction-dictation.md).

_Trigger > Capture > QR Code_ does the same trick for QR codes. Select the region with the code in it, and the decoded value goes to the clipboard. It only looks for QR codes — dense screen content has a habit of false-positiving as a barcode otherwise. Worth knowing: the decoded value goes to the clipboard and nowhere else. It isn't printed, it isn't in the notification, and it's marked sensitive so it doesn't stick around in [clipboard history](08-unified-clipboard-history.md). QR codes routinely carry secrets — the `otpauth://` URI behind a 2FA setup code, for one — and you don't want that in a log. Pasting still works fine.

`Super + Print Screen` (or _Trigger > Capture > Color_) turns the cursor into an eyedropper. Click anything on screen and the colour lands on the clipboard. Press the hotkey again to back out without picking.

## Transcoding before you share

A 4K screen recording or a raw HEIC off your phone is often too big to just send. `Super + Ctrl + .` (or _Trigger > Transcode_) fixes that. It offers you a fuzzy file picker over `~/Pictures` and `~/Videos`, then asks for a format and a size.

Pictures go to jpg or png at high, medium, or low, which cap the width at 3160, 2160, and 1080 pixels. Videos go to mp4 or an animated gif at 4k, 1080p, or 720p. The converted file is written next to the original with the resolution in the name — `demo-1080p.mp4` — and the path is copied to the clipboard as a file URI, so you can paste it directly into an app that takes file drops.

It works from the terminal too, if you already know what you want: `omarchy transcode ~/Videos/demo.mov mp4 1080p`. There's also `omarchy transcode ascii`, which turns an image into ASCII art — that one's mostly for [branding](41-branding.md).

## Sending it somewhere

Once you've got the file, `Super + Ctrl + S` opens the Share menu and sends it to another device on your network via LocalSend. See [GUIs](22-guis.md) for that.
