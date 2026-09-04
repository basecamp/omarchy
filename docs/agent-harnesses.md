# Coding-agent harnesses

Omarchy treats a coding agent as declarative metadata that describes how to install and launch it with an optional project and prompt. Third-party harnesses are delivered through the existing plugin system: install the integration with `omarchy plugin add`, update it with `omarchy plugin update`, and remove it with `omarchy plugin remove`.

A harness is not a new plugin kind. It is optional `agentHarness` metadata on a normal plugin manifest. A plugin that declares `agentHarness` may use `"kinds": []` and `"entryPoints": {}` when it has no Quickshell UI; the registry treats it as installed metadata and never tries to load it. Ordinary plugins still need at least one supported `kind` and matching `entryPoint`. The harness is available whenever its plugin is installed; enabling applies only to any Quickshell entry points the plugin also declares.

Built-in harnesses live in `default/agents/harnesses.json`. A third-party plugin can expose one from its root `manifest.json`; this example is a harness-only plugin, so it deliberately has no QML entry point:

```json
{
  "schemaVersion": 1,
  "id": "acme.agent-integration",
  "name": "Acme agent integration",
  "version": "1.0.0",
  "description": "Adds the Acme coding-agent harness",
  "kinds": [],
  "entryPoints": {},
  "agentHarness": {
    "id": "acme-agent",
    "name": "Acme Agent",
    "aliases": ["acme"],
    "icon": "󰚩",
    "install": {
      "type": "mise",
      "package": "npm:@acme/agent",
      "command": "acme-agent"
    },
    "launch": {
      "mode": "terminal",
      "command": ["acme-agent", "--accept"],
      "promptCommand": ["acme-agent", "--accept", "--prompt", "{prompt}"]
    }
  }
}
```

Install and select it normally:

```bash
omarchy plugin add https://github.com/acme/omarchy-acme-agent.git
omarchy default agent acme-agent
```

Only `mise` installation is accepted for third-party harnesses. The package must be a non-empty package reference, never an option or a value containing a newline. `command` and `promptCommand` are argv arrays, not shell snippets. The only substitutions are `{project}` and `{prompt}`; other brace-delimited placeholders are rejected. A launch mode is either `terminal`, which opens Omarchy's standard agent terminal, or `browser`, which runs directly for browser-first harnesses. A harness-only plugin is available as soon as it is installed and cannot be enabled because it has no shell component. Removing its plugin clears it as the default harness if it was selected; updating it clears the selection when its harness identity changes or is removed. Harness IDs and aliases cannot conflict with another integration when adding or updating; existing legacy conflicts remain deterministic but emit a warning so they can be repaired. Plugin installation already requires explicit trust and rejects unsafe manifests and symlinks; harness metadata adds no arbitrary installation hook.
