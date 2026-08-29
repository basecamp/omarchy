# mise-managed tools

Read this before adding or changing a mise-managed tool, including entries in `install/user/mise.sh` and calls to `omarchy-mise-install`.

Use a mise registry shorthand such as `codex` or `hey-cli`. Do not add an explicit backend such as `github:owner/repo`, `aqua:owner/repo`, or `npm:package`.

Before adding a tool, run `mise registry <name>` to confirm that its shorthand exists. The shorthand may differ from the installed binary name, so inspect the result instead of assuming they match.

If the tool is missing, stop and request an upstream mise registry entry. Include the upstream repository or package URL and the binary Omarchy needs. Do not work around a missing entry with explicit backend syntax; wait for the registry entry before adding the tool to Omarchy.

Registry shorthands let mise use <https://mise-versions.jdx.dev> for cached version and public GitHub release metadata. This avoids most unauthenticated GitHub API calls and reduces rate-limit failures and GitHub flakiness during Omarchy installs and updates.
