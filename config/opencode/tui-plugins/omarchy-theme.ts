import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import type { TuiPlugin } from "@opencode-ai/plugin/tui"

// Hot-reloads the Omarchy theme into running opencode TUIs. Omarchy rewrites
// themes/omarchy.json on every theme change; this watches the file and swaps
// the live theme, so running agents are never interrupted.
//
// Live retint is the default: "omarchy", "system" (follow-the-desktop, which
// used to depend on SIGUSR2), and generated omarchy-<hash> names all opt in.
// Picking any other theme in the picker opts out.
//
// theme.install() re-upserts content only while the theme is unknown to the
// registry, so each new palette is installed under a content-hashed name and
// older copies are pruned again. Install and prune only run while this session
// is opted in -- otherwise the plugin stays off the registry.

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
  // Truthy fallbacks on purpose: an empty-but-set OPENCODE_CONFIG_DIR or
  // XDG_CONFIG_HOME must resolve the same way omarchy-theme-set-opencode's
  // "${VAR:-...}" defaults do, or the watcher and the sync command diverge.
  const config =
    process.env.OPENCODE_CONFIG_DIR ||
    path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "opencode")
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

  const generatedName = new RegExp(`^${THEME_NAME}-[0-9a-f]{8}$`)
  const owned = () => {
    const selected = api.theme.selected
    return selected === THEME_NAME || selected === "system" || generatedName.test(selected)
  }

  const apply = async () => {
    if (!owned()) return

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
    // Unresolved theme-template tokens would crash resolveTheme(); skip the file.
    if (JSON.stringify(colors).includes("{{")) return

    const name = `${THEME_NAME}-${contentHash(text)}`
    const stale = (candidate: string) =>
      candidate !== `${name}.json` && new RegExp(`^${THEME_NAME}-[0-9a-f]{8}\\.json$`).test(candidate)

    try {
      if (!api.theme.has(name)) {
        // A per-apply temp directory keeps concurrent opencode sessions from
        // racing over one shared staged file; the file's basename must stay
        // `${name}.json` because theme.install() derives the theme name from it.
        const stagedDir = fs.mkdtempSync(path.join(os.tmpdir(), `${THEME_NAME}-theme-`))
        try {
          const staged = path.join(stagedDir, `${name}.json`)
          fs.writeFileSync(staged, text)
          await api.theme.install(staged)
        } finally {
          fs.rmSync(stagedDir, { recursive: true, force: true })
        }
      }
      if (api.theme.selected !== name) api.theme.set(name)
      for (const candidate of pruned) {
        for (const entry of fs.existsSync(candidate) ? fs.readdirSync(candidate) : []) {
          if (stale(entry)) fs.rmSync(path.join(candidate, entry), { force: true })
        }
      }
    } catch {}
  }

  // Serialize applies: theme.install() awaits, so a newer file event must not
  // interleave with an apply still finishing -- otherwise a stale invocation
  // could resume afterwards and set an older palette or prune the newer copy.
  // Each apply re-reads the file when it starts, so the last one always wins.
  let chain: Promise<void> = Promise.resolve()
  const enqueueApply = () => (chain = chain.then(apply).catch(() => {}))

  const schedule = () => {
    if (pending) clearTimeout(pending)
    pending = setTimeout(() => {
      pending = undefined
      void enqueueApply()
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

  await enqueueApply()
}

export default {
  id: "omarchy-theme",
  tui: plugin,
}
