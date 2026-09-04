# Coding-agent harnesses

Omarchy treats a coding agent as declarative metadata that describes how to install and launch it with an optional project and prompt. Third-party harnesses are delivered through the existing plugin system: install the integration with `omarchy plugin add`, update it with `omarchy plugin update`, and remove it with `omarchy plugin remove`.

A harness is not a new plugin kind. It is optional `agentHarness` metadata on a normal plugin manifest. The plugin must still declare at least one supported `kind` and matching `entryPoint`; a harness-only integration can use a minimal `service` entry point when it has no desktop UI. The harness is available whenever the plugin is installed; enabling controls its Quickshell entry point separately.

Built-in harnesses live in `default/agents/harnesses.json`. A third-party plugin can expose one from its root `manifest.json`:

```json
{
  "schemaVersion": 1,
  "id": "acme.agent-integration",
  "name": "Acme agent integration",
  "version": "1.0.0",
  "description": "Adds the Acme coding-agent harness",
  "kinds": ["service"],
  "entryPoints": { "service": "Service.qml" },
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

Only `mise` installation is accepted for third-party harnesses. `command` and `promptCommand` are argv arrays, not shell snippets. The only substitutions are `{project}` and `{prompt}`. A launch mode is either `terminal`, which opens Omarchy's standard agent terminal, or `browser`, which runs directly for browser-first harnesses. Plugin installation already requires explicit trust and rejects unsafe manifests and symlinks; harness metadata adds no arbitrary installation hook.
