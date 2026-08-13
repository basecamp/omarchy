# AI

Omarchy treats AI coding agents as first-class citizens, but it doesn't pick a favorite for you. Instead, every major coding-agent CLI comes pre-wired as a lazy-loaded launcher. The launchers are tiny [mise](https://mise.jdx.dev/)-managed stubs in `~/.local/bin/`, so nothing is downloaded until the first time you actually run one. Invoke any of these and authenticate when prompted:

| Command    | Agent                                                            |
|------------|------------------------------------------------------------------|
| `claude`   | [Claude Code](https://code.claude.com/docs/en/overview)          |
| `codex`    | [OpenAI Codex](https://github.com/openai/codex)                  |
| `opencode` | [OpenCode](https://opencode.ai/)                                 |
| `gemini`   | [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) |
| `copilot`  | [GitHub Copilot CLI](https://github.com/github/copilot-cli)      |
| `crush`    | [Crush](https://github.com/charmbracelet/crush)                  |
| `grok`     | Grok CLI from xAI                                                |
| `pi`       | [Mario Zechner's Pi](https://github.com/badlogic/pi-mono)        |
| `omp`      | [Oh My Pi](https://github.com/can1357/oh-my-pi)                  |

To wrap an additional CLI the same way, run `omarchy-mise-install <package> [command-name]`. The stubs are kept current along with everything else mise manages when you run `omarchy update` (or the `mup` alias).

### The default agent

Pick your default agent with `omarchy default agent <name>` or under _Setup > Defaults > Agent_ in the Omarchy Menu (`Super + Space`). If the agent isn't installed yet, picking it installs it first. A fresh Omarchy will invite you to make this choice with a one-time notification.

Once you've chosen, `Super + Shift + Ctrl + A` launches the default agent in a dedicated terminal window (or brings up the picker if you haven't chosen yet). You can also launch it straight into a task with `omarchy agent prompt "Review this project"`. Agents launched this way run unattended in their respective don't-stop-to-ask modes, so be ready for them to actually do things! And since agents refuse to remember trust for your home directory, launches from `$HOME` start in `~/Work` instead.

There are terminal shortcuts too: `a` runs the default agent inline in the current terminal, while `c`, `cx`, and `cy` start OpenCode, Claude Code, and Codex directly (again in their auto-approving modes). Theme changes sync to the agents as well: Claude Code, Pi, and OpenCode all follow along when you switch the Omarchy theme.

### The agents panel

The top bar grows an agents icon the first time Omarchy finds AI coding usage on the machine (and stays out of the way until then). The panel behind it tracks every subscription in one place: your plan, the percentage used of the 5-hour session and weekly limits (or the remaining prepaid balance), and token usage by day and by model. Claude Code, Codex, and Fireworks are covered out of the box.

Left-click the bar icon for the panel, right-click to launch your default agent. The usage records behind it are regenerated every 15 minutes by `omarchy agent usage-update`, and the panel can even merge usage from your other machines via a synced folder. See the README under `$OMARCHY_PATH/shell/plugins/agents/` for the full settings.

### Crash diagnosis

Omarchy watches systemd-coredump for process crashes. When something segfaults, you'll get a "Process crashed" notification — click it, and the crash is handed to your default agent along with Omarchy's diagnose-crash skill, which walks the agent through establishing the facts from the core dump and deciding whether the crash is worth reporting upstream. You can also run it by hand against any PID from `coredumpctl list` with `omarchy agent crash <pid>`.

The watching is on by default. Turn it off under _Trigger > Toggle > Crash Capture_ (or with `omarchy toggle crash-capture`) and the notifications stop; `omarchy agent crash <pid>` still works by hand.

### Desktop apps

The _Install > AI_ menu also carries a couple of graphical AI apps: the ChatGPT desktop app, and Grok Bot for chatting with xAI's models.

### Local LLMs

Omarchy recommends two ways of running local LLM models: LM Studio and Ollama. LM Studio provides a GUI interface for finding open-weight models, installing them, and running them. It's a great way to get going easily. Ollama offers a CLI for doing so similarly. But if you're new to local models, I'd start with LM Studio. You can install either under _Install > AI_ in the Omarchy Menu.

### The Omarchy Skill

Agent skills help AI use specific tools in a specific way, and Omarchy ships with a default skill for tailoring the system. Like tweaking your Hyprland config, adjusting the bar, or even creating a new theme from scratch. It's symlinked into the skill directories for Claude Code (`~/.claude/skills`), Codex (`~/.codex/skills`), Pi (`~/.pi/agent/skills`), and the generic `~/.agents/skills` location, so most harnesses pick it up automatically.

But you should treat this skill as experimental. Different models will use it to different effect. It's best to run in plan mode first, so you have an idea of what the agent would like to change. And then be ready to rollback changes or even invoking `omarchy reinstall configs`, if the agent makes a mess of everything.
