# Omarchy CLI

Omarchy is usually controlled through the hotkeys and the Omarchy menu (`Super + Alt + Space`). But you can also control it through the `omarchy` CLI. This is particularly helpful when you're having an AI agent work with you on customization or configuration.

The CLI has access to all the internal tooling that is used both via the menu and otherwise. You can see everything that's available by running `omarchy` in the terminal.

It looks something like this:

```
~ ❯ omarchy
Omarchy command center

Usage:
  omarchy <command> [args...]
  omarchy commands [--all] [--json] [--check]
  omarchy <group> --help
  omarchy <group> <command> --help

Common commands:
  omarchy update              Update Omarchy and system packages
  omarchy theme list          List available themes
  omarchy theme set <name>    Apply a theme
  omarchy font list           List available fonts
  omarchy screenshot          Take a screenshot
  omarchy debug               Print debugging information

Groups:
  ac             AC power detection
  battery        Battery status helpers
  branch         Omarchy git branch management
  brightness     Display and keyboard brightness
  capture        Screenshots and screen recording
  channel        Omarchy release channel management
  cmd            Command and shortcut helpers
  config         System configuration helpers
  debug          Diagnostics and support logs
  dev            Omarchy development tools
  drive          Drive selection and encryption
  font           Font management
```

And you can dive deeper on every group:

```
~ ❯ omarchy capture
Capture commands — Screenshots and screen recording:
  omarchy capture screenrecording [--with-desktop-audio] [--with-microphone-audio] [--with-webcam] [--webcam-device=<device>] [--resolution=<size>] [--stop-recording]  Start or stop screen recording
  omarchy capture screenshot [smart|region|windows|fullscreen] [slurp|copy] [--editor=<name>]                                                                           Take a screenshot
  omarchy capture text extraction                                                                                                                                       Extract text from a screenshot region with OCR
```
