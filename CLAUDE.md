# Omarchy Fork

Personal fork of [basecamp/omarchy](https://github.com/basecamp/omarchy) adapted for CachyOS.

## Key References

- **`AGENTS.md`** — Code style, command naming, helper commands, config structure, refresh pattern, migrations
- **`/omarchy` skill** — Fork convention (`# [omarchy]` comments), `omarchy-fork-*` naming rules, CachyOS-specific patterns

## After Upstream Sync

After merging upstream changes (`git merge upstream/master`), check for new/updated default configs:

1. **Diff the `config/` folder** between pre-merge and post-merge: `git diff HEAD~1..HEAD -- config/`
2. **Compare each changed file** against the user's local `~/.config/` version
3. **Only flag functional changes** — bug fixes, new features, new modules. Skip:
   - Comment-only additions (documentation examples)
   - Personal preference differences (font sizes, keyboard layouts, monitor configs, theming)
   - Files the user has intentionally customized
4. **Push upstream tags to fork** — `git push origin --tags` (otherwise waybar shows a false update icon because `omarchy-update-available` compares local vs remote tags)
5. **Audit `# [omarchy]` comments** — check if upstream removed any lines we commented out. If upstream also deleted a line, remove our `# [omarchy]` comment to stay in sync: `grep -rn '\[omarchy\]' . --include='*.sh' --include='*.conf' --include='*.packages'` then compare each with `git show upstream/master:<file>`
6. **Apply fixes** the user confirms, then restart affected services (e.g. `omarchy-restart-waybar`)
