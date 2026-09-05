# mise-managed tools

Read this before adding or changing a mise-managed tool, including entries in `install/user/mise.sh` and calls to `omarchy-mise-install`.

When a tool is available through `github:` or `aqua:`, use its mise registry shorthand such as `codex` or `hey-cli` instead of spelling out the backend. Other explicit backends, such as `pipx:`, may be used when their backend-specific behavior or options are required.

Before adding a GitHub- or Aqua-backed tool, run `mise registry <name>` to confirm that its shorthand exists. The shorthand may differ from the installed binary name, so inspect the result instead of assuming they match.

If the GitHub- or Aqua-backed tool is missing, stop and request an upstream mise registry entry. Include the upstream repository or package URL and the binary Omarchy needs. Do not work around a missing entry with explicit `github:` or `aqua:` syntax; wait for the registry entry before adding the tool to Omarchy.

Registry shorthands let mise use <https://mise-versions.jdx.dev> for cached version and public GitHub release metadata. This avoids most unauthenticated GitHub API calls and reduces rate-limit failures and GitHub flakiness during Omarchy installs and updates.
