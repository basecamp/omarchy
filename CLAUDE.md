# Omarchy Fork

Personal fork of [basecamp/omarchy](https://github.com/basecamp/omarchy) adapted for CachyOS.

## Omarchy Skill

Always use the `/omarchy` skill when editing fork files. It contains the fork convention (`# [omarchy]` comments), `omarchy-fork-*` naming rules, and CachyOS-specific patterns.

## After Upstream Sync

After merging upstream changes (`git merge upstream/master`), check for new/updated default configs:

1. **Diff the `config/` folder** between pre-merge and post-merge: `git diff HEAD~1..HEAD -- config/`
2. **Compare each changed file** against the user's local `~/.config/` version
3. **Only flag functional changes** — bug fixes, new features, new modules. Skip:
   - Comment-only additions (documentation examples)
   - Personal preference differences (font sizes, keyboard layouts, monitor configs, theming)
   - Files the user has intentionally customized
4. **Apply fixes** the user confirms, then restart affected services (e.g. `omarchy-restart-waybar`)
