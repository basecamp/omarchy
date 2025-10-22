#!/usr/bin/env python

# Author: Esteban Cuevas
# Email: esteban at attitude.cl
# URL: https://github.com/EstebanForge/nautilus-backspace-nav
# License: MIT License

"""
Nautilus Extension: Backspace to Go Up Folder
Enables backspace key navigation in Nautilus file manager to go up one directory level.

This extension adds the familiar backspace navigation behavior found in other file managers,
allowing users to press the Backspace key to navigate to the parent directory.

Back folder behavior is not triggered when editing text fields, such as renaming files,
searching, or using the path bar. This ensures that the extension does not interfere with
normal text editing operations. The backspace navigation is implemented using the
activate_action("slot.up", None) method, which is the standard Nautilus action for
navigating up in the file hierarchy.

Key Features:
- Implements backspace navigation using InfoProvider and key controllers
- Attaches to both new and existing Nautilus windows
- Preserves normal backspace behavior in text fields
- Uses native Nautilus up navigation action

Technical Details:
- Requires GTK 4.0 and Nautilus 4.0
- Uses GObject inheritance for Nautilus extension integration
- Implements window monitoring via application signals
- Handles key events through Gtk.EventControllerKey
- Safe-guards against multiple controller attachments

Installation:
1. You need to install nautilus-python and its dependencies. On Fedora 41:

    sudo dnf install nautilus-python

2. Download this script and save it into the Nautilus extensions directory:
    ~/.local/share/nautilus-python/extensions/

3. Restart Nautilus to load the extension:
    nautilus -q
Or simply log out and log back in to your session.

4. Open Nautilus and navigate to a folder. Press the Backspace key to go up one level.
As stated before, the normal text deletion behavior is preserved when editing file
names, using search or using the path bar.
"""

import gi
import os

# Try to ensure minimum versions
try:
    gi.require_version('Nautilus', '4.0')
    gi.require_version('Gtk', '4.0')
    gi.require_version('Gdk', '4.0')
except ValueError as e:
    # Log critical error if imports fail, maybe to system log or stderr
    print(f"[BackspaceNav] ERROR: Missing required GTK/Nautilus version ({e}). Extension cannot load.", file=os.sys.stderr)
    import sys
    sys.exit(1)

from gi.repository import GObject, Nautilus, Gtk, Gdk

# Inherit from InfoProvider as required by the environment
class BackspaceNav(GObject.GObject, Nautilus.InfoProvider):
    """
    Implements Backspace navigation using InfoProvider inheritance
    and key controllers attached via the window-added signal.
    Uses activate_action for navigation.
    """

    def __init__(self):
        app = Gtk.Application.get_default()
        if not app:
            print("[BackspaceNav] ERROR: Could not get Gtk.Application.get_default().", file=os.sys.stderr)
            return

        app.connect("window-added", self.on_window_added)

        # Apply to existing windows
        windows = app.get_windows()
        for window in windows:
            if isinstance(window, Gtk.ApplicationWindow):
                 self.setup_controller_for_window(window)

    # Required by Nautilus.InfoProvider
    def update_file_info(self, file: Nautilus.FileInfo):
        # Required method for InfoProvider interface. Does nothing here
        pass

    # Window Handling
    def on_window_added(self, application: Gtk.Application, window: Gtk.Window):
        # Callback for when a new window is added to the application
        if isinstance(window, Gtk.ApplicationWindow):
            self.setup_controller_for_window(window)

    def setup_controller_for_window(self, window: Gtk.Window):
        # Attaches the key controller to a given window
        # Use a unique attribute name to check if controller is already attached
        if hasattr(window, '_backspace_nav_controller_attached_clean_'):
             return # Already attached

        key_controller = Gtk.EventControllerKey.new()

        try:
            key_controller.connect("key-pressed", self.on_key_pressed, window)
            window.add_controller(key_controller)
            # Mark the window so we don't add the controller multiple times
            setattr(window, '_backspace_nav_controller_attached_clean_', True)
        except Exception as e:
             print(f"[BackspaceNav] ERROR setting up controller: {e}", file=os.sys.stderr)

    # Key Press Logic
    def on_key_pressed(self, controller: Gtk.EventControllerKey, keyval: int, keycode: int, state: Gdk.ModifierType, window: Gtk.Window):
        # Handles key press events for the window
        # Check if plain Backspace (no Shift/Ctrl/Alt) was pressed
        if keyval == Gdk.KEY_BackSpace and not (state & Gtk.accelerator_get_default_mod_mask()):
            focused_widget = window.get_focus()
            is_editing = focused_widget is not None and isinstance(focused_widget, Gtk.Editable)

            # Action: Navigate Up (Using activate_action)
            if not is_editing:
                try:
                    # Activate the standard Nautilus action for navigating up on the window
                    window.activate_action("slot.up", None)
                    # Return True: We handled the event, stop further processing
                    return True
                except Exception as e:
                     # Log error if action fails
                     print(f"[BackspaceNav] ERROR activating action 'slot.up': {e}", file=os.sys.stderr)
                     # Return False on error to allow potential default handling
                     return False

            # Action: Allow Default (Editing)
            else:
                # Return False: Let the event propagate so the default Backspace (delete character) works
                return False

        # Propagate event if not handled (not Backspace, or had modifier, etc.)
        return False
