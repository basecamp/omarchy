# Coding Agents

Use this guide for the installed system's coding-agent launcher, repository instruction files, skills, and MCP setup. Query `omarchy commands --json` for the current CLI surface rather than copying its command catalog here.

## Repository Instructions

Before working in a repository, walk from the repository root toward the working directory and read the instruction files supported by the selected agent. Common entry points include `AGENTS.md` and `CLAUDE.md`; treat the repository's own file as authoritative about precedence. A small `AGENTS.md` may point to a canonical `CLAUDE.md` or another shared contract. Follow that pointer instead of restating its contents, because duplicated rules drift.

Chat history is not durable shared state. Put facts that every future agent needs in a committed instruction or documentation file, and put task evidence in the repository's documented handoff location. Never put secrets, transient status, or machine-specific credentials in shared instructions.

If two applicable instruction files conflict and neither declares precedence, stop and report the conflict. Do not guess which agent-specific file wins.

## Launch Policy

`omarchy agent` and `omarchy agent prompt` launch the configured default agent using Omarchy's autonomous approval profile. This is suitable only when the user has authorized autonomous changes within the current working directory and understands that the agent may act without pausing for each tool call.

For an approval-first session, use `omarchy agent --safe` or `omarchy agent prompt --safe <prompt>`. Use `--auto` only when autonomous operation is explicitly appropriate. Query the current route metadata and help because supported flags may change with the installed version. If launching the selected agent's native CLI instead, omit auto-approval, bypass-permissions, and yolo flags and check that CLI's current help. State which policy is active before beginning consequential work.

Keep authorization scope separate from persistence: autonomous mode does not authorize unrelated repositories, package-owned files, credential changes, deletion, publishing, or external messages.

## Skills

The Omarchy skill installed under `/usr/share/omarchy/default/agents/skills/` is package-owned. User-facing tasks may read it, but must not edit it; an update will overwrite local changes. Its links in agent-specific skill directories may be symlinks to that packaged copy, so resolve a path before editing.

Develop a personal or experimental skill in a user-owned skill directory. Contribute improvements to the Omarchy source repository when they belong in the packaged skill. Avoid copying the packaged skill merely to patch it: two skills with the same purpose or name can confuse discovery and silently drift.

## MCP Diagnostics

Use the read-only `omarchy agent doctor`, `omarchy agent mcp list`, and `omarchy agent mcp doctor` diagnostics. Add `--json` when another tool will consume the result. Query their current help and JSON output rather than encoding their fields in this guide. They consolidate discovery but do not replace each agent's native configuration format:

1. Identify the selected agent and confirm its binary and version.
2. Run Omarchy's MCP list/doctor route, then use that agent's help when native detail is needed.
3. Inspect configured server names, transports, executable paths or URLs, and required environment-variable names. Redact values.
4. Check whether local executables exist, remote endpoints are reachable, and authentication is present without printing tokens.
5. Separate “configured” from “reachable” and “authenticated” in the report.
6. Make changes only in the selected agent's user-owned config, then rerun its diagnostics.

Keep secrets in the agent's supported credential store or environment references, not literal values in repository instructions or portable MCP templates. When several agents need the same server, document the intended server and variable names once, but generate or maintain each agent's native configuration explicitly; do not assume their schemas or permission models are interchangeable.

## Handoff Checklist

- Name the selected agent, version, and active approval policy.
- List the instruction files actually read and any declared precedence.
- Report skills as packaged, user-owned, or broken links.
- Report MCP servers separately as configured, reachable, and authenticated.
- Record durable non-secret conclusions in the repository's canonical documentation.
