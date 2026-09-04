# Brokered command executor

`omarchy-plugin-command-executor` is the generic trusted provider for `bash.execute/run`. Despite the capability namespace, it never starts Bash or another shell. It accepts only a structured command name plus an argv array, selects the exact profile named by the already-authorized manifest scope, and executes a descriptor-pinned absolute path without PATH lookup or command-string parsing.

The packaged provider profile starts one executor per plugin activation only after an authorized call. It reads package policies from `/usr/lib/omarchy/plugin-security/<version>/commands.d` and optional administrator policies from `/etc/omarchy/plugin-command-profiles.d`. Both roots, every ancestor, and every policy must be owned by root and not group- or world-writable in the production process. A missing package root, malformed document, symlink, duplicate profile, unknown key, shell command, or excessive bound rejects the complete executor before it accepts requests.

Each `*.policy` file contains exactly one profile:

```json
{
  "schemaVersion": 1,
  "profile": "example-api-v1",
  "command": "example",
  "executable": "/usr/bin/example",
  "timeoutMs": 10000,
  "stdoutBytes": 32768,
  "stderrBytes": 4096,
  "accountHome": false,
  "environment": {
    "NO_COLOR": "1"
  },
  "rules": [
    [
      {"exact": "status"},
      {"regex": "[0-9]{1,8}"}
    ]
  ]
}
```

Each rule matches one complete argv vector. An `exact` matcher compares one argument byte-for-byte. A `regex` matcher is automatically anchored to the complete UTF-8 argument; it never spans arguments or produces shell text. Rules cannot be empty unless the approved command genuinely takes no arguments. Policy documents are trusted code-review artifacts, so broad expressions such as `.*` must be treated as broad authority.

The executor always supplies only `PATH=/usr/bin`, `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, and a fixed `HOME`. `accountHome: false` uses `/nonexistent`; `true` resolves the runtime account's home directory for tools with an explicitly approved credential store. A profile may add fixed environment entries, but cannot replace PATH, HOME, locale, dynamic-loader, or Qt variables. Nothing is inherited from the shell environment.

The target executable and every path component are revalidated, opened with `O_NOFOLLOW`, and retained by descriptor before `execveat`. The child receives `/dev/null` on stdin, captured bounded stdout/stderr, `PR_SET_NO_NEW_PRIVS`, a new process group, and no unrelated descriptors. Timeout or output overflow kills the complete command process group. The enclosing provider activation remains inside its systemd resource scope and tears down that entire scope on revocation or provider-protocol failure.

The core package ships one reviewed `github-api-v1` policy for the GitHub dashboard plugin. It admits only the fixed authentication probe, dashboard REST/GraphQL reads, Actions queries, and notification updates used by that plugin. Token display, input files, arbitrary endpoints, alternate hosts, extensions, aliases, repository inference, formatting hooks, and other `gh` commands remain outside the grammar. Additional service integrations must add a reviewed root-owned policy, request its exact profile in the plugin manifest, and test both its accepted argv language and privilege-escalating near misses.
