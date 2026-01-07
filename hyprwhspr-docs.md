# HyprWhisper Configuration

## 1. Hyprland Integration

Add the binding to your `~/.config/hypr/hyprland.conf`. 
Ensure the script path matches where you saved `transcribe.sh`.

```ini
# Voice Dictation (Toggle)
bind = SUPER, R, exec, ~/hyprwhspr/transcribe.sh
```

**⚠️ Important:** `SUPER+R` is often used by default for application launchers or "Submap" modes. Ensure you comment out or change any existing bindings for `SUPER+R` to avoid conflicts.

*Note: Reload Hyprland with `hyprctl reload`.*

---

## 2. Waybar Integration (Visual Indicator)

This adds a flashing red recording button to your status bar when the script is active.

### Step A: Add Module to Config
Edit `~/.config/waybar/config` (or `.jsonc`) and add `"custom/recorder"` to your `modules-right`, `modules-center`, or `modules-left` list.

Then add the module definition at the bottom of the file:

```json
"custom/recorder": {
    "format": "🎙️ Rec",
    "format-alt": "🎙️ Rec",
    "return-type": "json",
    "interval": 1,
    "exec": "echo '{\"class\": \"recording\"}'",
    "exec-if": "test -f /tmp/whisper_rec.pid"
}
```

### Step B: Add Styles
Edit `~/.config/waybar/style.css`. This CSS makes the button red and blink when active.

```css
#custom-recorder {
    background-color: #ff0000;
    color: #ffffff;
    padding: 0 10px;
    margin: 0 5px;
    border-radius: 5px;
    font-weight: bold;
    /* Optional: Blinking Animation */
    animation-name: blink;
    animation-duration: 1s;
    animation-timing-function: linear;
    animation-iteration-count: infinite;
    animation-direction: alternate;
}

@keyframes blink {
    to {
        background-color: #bf0000;
    }
}
```

*Note: Restart Waybar (e.g., `killall waybar; waybar &`) to see changes.*

---

## 3. Troubleshooting

**1. "No speech detected"**
* Check your default microphone in `pavucontrol` or System Settings.
* Ensure `pulseaudio-utils` is installed (needed for `parecord`).

**2. Script permission denied**
* Run: `chmod +x ~/hyprwhspr/transcribe.sh`

**3. Notification not showing**
* Ensure a notification daemon is running (e.g., `dunst`, `mako`, or `swaync`).

**4. Wrong Model Path**
* If you changed the directory structure manually, verify the `WHISPER_DIR` variable inside `transcribe.sh` points to the folder containing the `models` and `build` directories.