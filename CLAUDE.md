# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when
working with code in this repository.

## Build & Test Commands

- `nix flake check` — Validates the entire configuration by
  building a test NixOS system with omarchy enabled
- `nix fmt <files>` — Format nix files (uses nixfmt)
- `dev-mode` — File watcher that auto-runs `nix flake check`
  on changes (available in `nix develop`)
- `lint` / `lint --fix` — Run statix and deadnix linting
  (available in `nix develop`)

## Critical Rules

### Tool Paths: Always Explicit, Never PATH

**NEVER** rely on tools being in PATH. Always substitute full
nix store paths into config files using `@variable@` placeholders
and `pkgs.replaceVars`. This serves two purposes:

1. **Precision** — explicit dependencies, no ambient state
2. **Upstream visibility** — when rebasing on upstream omarchy,
   our `@variable@` substitutions create merge conflicts,
   making every upstream change easy to spot and review

This means config files in `default/` will have `@tool@`
placeholders where upstream has bare command names.

### Path Literals

Always wrap path literals in `builtins.path { path = ...; }`
when using them as file sources. Bare path literals cause
subtle issues.

### Nix Flake Basics

- When creating new `.nix` files, immediately `git add` them.
  Nix flakes only see git-tracked files — builds will fail on
  untracked files.
- The hyprland package comes from a flake input, not nixpkgs.
  Always use `cfg.hyprland.package` (or the NixOS option
  equivalent), never `pkgs.hyprland`.
- Similarly, `xdg-desktop-portal-hyprland` must use the matching
  flake version via `portalPackage` options to avoid pulling in
  a second copy of hyprland from nixpkgs.

## Architecture

**Omarchy on NixOS** reproduces the Omarchy desktop experience
as Nix flake modules. It exports `nixosModules`,
`homeManagerModules`, and a `lazyvimTheme` for consumers.

### Module Structure

- `nix/modules/nixos.nix` — System-level module (hyprland,
  evince, nautilus, Qt theming). Imports sub-modules from
  `nix/modules/nixos/`.
- `nix/modules/home-manager.nix` — Core home-manager module.
  Imports all modules from `nix/modules/home/`.
- `nix/modules/home/options.nix` — Central options definition
  (theme, hyprland, terminal, font, keyboard, screensaver, etc.)
- `nix/modules/home/*.nix` — Individual app modules (hyprland,
  waybar, walker, mako, gtk, scripts, etc.)
- `nix/modules/nixos/sddm.nix` — Display manager (SDDM with
  Wayland, autologin, uwsm binPath override)
- `nix/modules/lazyvim-theme.nix` — Exports neovim theme lua
  from the selected omarchy theme

### Configuration Layers

- `default/` — Template configs with `@variable@` placeholders,
  processed by `pkgs.replaceVars` at build time
- `config/` — User-editable overrides, sourced after defaults
  (Hyprland sources these last so they win)
- `themes/{name}/colors.toml` — Palette definitions injected
  into templates across all apps

### Scripts

`bin/` contains 40+ `omarchy-*` scripts. They're packaged by
`nix/modules/home/scripts.nix` using a `createScript` helper
that does variable substitution for tool paths.

#### Script Placeholder Format

Scripts use `@exe@` placeholders (not `@pkg@/bin/exe`):

```bash
#!@bash@/bin/bash
@jq@ -r '.foo' | @grep@ bar
```

The shebang is the exception — it needs the full path form.

#### Script Dependencies in scripts.nix

Define executables once in the `exe` attrset, then use `inherit`:

```nix
with builtins;
let
  inherit (lib) getExe getExe';

  exe = {
    # Packages with meta.mainProgram — use getExe
    jq = getExe pkgs.jq;
    grep = getExe pkgs.gnugrep;

    # Packages without mainProgram — use explicit path
    hyprctl = getExe' hyprland "hyprctl";
    pactl = "${pkgs.pulseaudio}/bin/pactl";

    # Bash is special (shebang needs /bin/bash)
    bash = "${pkgs.bash}/bin/bash";
  };
in
```

Then reference via `inherit (exe)`:

```nix
(createScript "omarchy-example" {
  inherit (exe) bash jq grep;
})
```

Use the binary name as the placeholder name (`@grep@` not
`@gnugrep@`), and keep hyphens (`@notify-send@` not
`@notify_send@`).

### Theme System

14 themes in `themes/`. Each has `colors.toml` (hex palette),
optional `light.mode` flag, backgrounds, and app-specific theme
files. Colors are expanded into hex, stripped-hex, and RGB
variants, then injected into `.tpl` template files in
`default/themed/`.

## Coding Conventions

- Open files that use `builtins` with `with builtins;` so you
  can write `path { ... }` instead of `builtins.path { ... }`
- Use `inherit (lib) getExe getExe';` at the top of let blocks
- Use `inherit (exe) foo bar;` rather than `foo = exe.foo;`
- Use `inherit (cfg) theme;` to pull config values

## Module Patterns

- NixOS modules use `mkIf cfg.enable { ... }` where
  `cfg = config.omarchy`
- Home-manager modules follow the same pattern
- Terminal modules are mutually exclusive via
  `mkIf (cfg.terminal == "ghostty")` etc.
- New NixOS sub-modules go in `nix/modules/nixos/` and get
  imported from `nixos.nix`
- New home-manager modules go in `nix/modules/home/` and get
  imported from `home-manager.nix`

## Test Build

`nix flake check` builds a NixOS system with a fake `testuser`,
omarchy enabled, and minimal hardware config. This validates the
entire module tree evaluates and builds without needing real
hardware.

## Tech Debt

- Tool path substitution currently happens in the config files
  themselves (replacing command names with `@var@` placeholders).
  Ideally we'd provide executables directly as the replacement
  values rather than modifying the source files. Fire for later.
