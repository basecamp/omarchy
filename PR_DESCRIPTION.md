> **Note**: *This is my first-ever Pull Request to a major open-source project! If anything needs adjustment or doesn't fully meet the project standards, please let me know and I'll gladly update it.*

---

### Summary
This PR adds first-class **Doom Emacs** support to Omarchy, including automated installation via `omarchy-emacs`, installer/uninstaller scripts, default editor configuration (`EDITOR`/`VISUAL`), keybinding integration (`SUPER + SHIFT + N`), Walker / Omarchy menu entries, and live truecolor auto-theming for `emacsclient` daemon frames.

---

### Features & Changes Included

1. **Installer (`bin/omarchy-install-editor-doom-emacs`)**:
   - Installs `omarchy-emacs` AUR package (bundled fonts & GTK/PGTK integration) + core dependencies (`git`, `ripgrep`, `fd`, `findutils`).
   - Clones `https://github.com/doomemacs/core` into `~/.config/emacs`.
   - Runs Doom interactive setup in Omarchy's floating presentation terminal.
   - Configures PATH and sets `alias ec="emacsclient -c -a ''"`.
   - Sets Doom Emacs as default editor (`omarchy default editor doom`).

2. **Uninstaller (`bin/omarchy-remove-editor-doom-emacs`)**:
   - Safely removes `~/.config/emacs` and offers optional user config cleanup (`~/.config/doom`).

3. **Default Editor Support (`bin/omarchy-default-editor` & `bin/omarchy-launch-editor`)**:
   - Registered `doom` / `doom-emacs` in `omarchy-default-editor` with the Doom Skull glyph (`󰗡`).
   - Updated `omarchy-launch-editor` to handle `emacsclient` daemon frames (`emacsclient -c -a ''`) and inline terminal mode (`emacs -nw`).
   - `SUPER + SHIFT + N` shortcut seamlessly opens Doom Emacs when set as default.

4. **Walker / Omarchy Menu Entries (`default/omarchy/omarchy-menu.jsonc`)**:
   - **Install > Editor > Doom Emacs** (`install.editor.doom-emacs`)
   - **Setup > Defaults > Editor > Doom Emacs** (`setup.default.editor.doom`)
   - **Remove > Editor > Doom Emacs** (`remove.editor.doom-emacs`)

5. **Automated Truecolor Theming (`default/themed/doom-theme.el.tpl`, `default/themed/omarchy-colors.el.tpl` & `bin/omarchy-theme-set-emacs`)**:
   - Generates `~/.local/state/omarchy/current/theme/doom-theme.el` and `omarchy-colors.el` on theme changes natively without requiring external hook scripts or hook managers.
   - Automatically syncs `omarchy-colors.el` to `~/.config/doom/` and `~/.config/emacs/`.
   - Hot-reloads all active frames across theme changes smoothly without white frame flicker.

---

### Verification & Testing
- Ran `omarchy commands --check`: **Passed (398 commands)**.
- Verified `omarchy-install-editor-doom-emacs` execution and menu visibility in Walker.
- Verified `SUPER + SHIFT + N` launching Doom Emacs.
- Verified live theme switching and truecolor rendering in `ec` (`emacsclient`) mode.
