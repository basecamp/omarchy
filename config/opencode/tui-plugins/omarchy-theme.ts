import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import type { TuiPlugin } from "@opencode-ai/plugin/tui"

// Hot-reloads the Omarchy theme into running opencode TUIs. Omarchy rewrites
// themes/omarchy.json on every theme change; this watches the file and swaps
// the live theme, so running agents are never interrupted. The theme becomes
// active once selected -- through "theme": "omarchy" in tui.json or the theme
// picker -- and stays on the Omarchy palette until something else is picked.
//
// theme.install() re-upserts content only while the theme is unknown to the
// registry, so each new palette is installed under a content-hashed name and
// older copies are pruned again.

const THEME_NAME = "omarchy"
const DEBOUNCE_MS = 250

const REQUIRED_COLORS = [
  "primary",
  "secondary",
  "accent",
  "error",
  "warning",
  "success",
  "info",
  "text",
  "textMuted",
  "background",
  "backgroundPanel",
  "backgroundElement",
  "border",
  "borderActive",
  "borderSubtle",
]

function themesDir() {
  const config =
    process.env.OPENCODE_CONFIG_DIR ??
    path.join(process.env.XDG_CONFIG_HOME ?? path.join(os.homedir(), ".config"), "opencode")
  return path.join(config, "themes")
}

function contentHash(text: string) {
  let hash = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193)
  }
  return (hash >>> 0).toString(16).padStart(8, "0")
}

const plugin: TuiPlugin = async (api) => {
  const dir = themesDir()
  const file = path.join(dir, `${THEME_NAME}.json`)
  const pruned = new Set([dir, path.join(path.dirname(dir), ".opencode", "themes")])
  let watcher: fs.FSWatcher | undefined
  let pending: ReturnType<typeof setTimeout> | undefined

  const owned = () => {
    const selected = api.theme.selected
    return selected === THEME_NAME || selected.startsWith(`${THEME_NAME}-`)
  }

  const apply = async () => {
    let text: string
    try {
      text = fs.readFileSync(file, "utf8")
    } catch {
      return
    }

    let data: unknown
    try {
      data = JSON.parse(text)
    } catch {
      return
    }
    if (typeof data !== "object" || data === null || Array.isArray(data)) return
    const colors = (data as Record<string, unknown>).theme
    if (typeof colors !== "object" || colors === null) return
    if (REQUIRED_COLORS.some((key) => (colors as Record<string, unknown>)[key] === undefined)) return

    const name = `${THEME_NAME}-${contentHash(text)}`
    const stale = (candidate: string) =>
      candidate.startsWith(`${THEME_NAME}-`) && candidate !== `${name}.json` && candidate.endsWith(".json")

    try {
      if (!api.theme.has(name)) {
        const staged = path.join(os.tmpdir(), "omarchy-theme", `${name}.json`)
        fs.mkdirSync(path.dirname(staged), { recursive: true })
        fs.writeFileSync(staged, text)
        await api.theme.install(staged)
        fs.rmSync(staged, { force: true })
      }
      if (owned() && api.theme.selected !== name) api.theme.set(name)
      for (const candidate of pruned) {
        for (const entry of fs.existsSync(candidate) ? fs.readdirSync(candidate) : []) {
          if (stale(entry)) fs.rmSync(path.join(candidate, entry), { force: true })
        }
      }
    } catch {}
  }

  const schedule = () => {
    if (pending) clearTimeout(pending)
    pending = setTimeout(() => {
      pending = undefined
      void apply()
    }, DEBOUNCE_MS)
  }

  try {
    fs.mkdirSync(dir, { recursive: true })
    watcher = fs.watch(dir, (_event, filename) => {
      if (filename && filename !== `${THEME_NAME}.json`) return
      schedule()
    })
  } catch {
    return
  }

  api.lifecycle.onDispose(() => {
    if (pending) clearTimeout(pending)
    watcher?.close()
  })

  await apply()
}

export default {
  id: "omarchy-theme",
  tui: plugin,
}
