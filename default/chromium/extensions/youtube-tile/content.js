/* ---------------------------------------------------------------------------
 * YouTube Tile Mode — content script
 *
 * The problem this solves: in the `--app` YouTube window, YouTube's own
 * fullscreen (`f`) calls the Fullscreen API, which makes Hyprland promote the
 * window to monitor fullscreen and rip it out of the tiling layout. There is
 * no built-in way to say "just fill this tile with the video".
 *
 * Tile mode is that missing state: the player fills the window, the window
 * stays exactly where the tiling layout put it.
 * ------------------------------------------------------------------------- */

const DEFAULTS = {
  autoTile: true, // enter tile mode automatically when a video opens
  fill: false, // crop the video to the tile instead of letterboxing
  remapF: true, // f -> tile mode, Shift+F -> real (monitor) fullscreen
  wideGrid: true, // let the video grid use the tile's full width
};

let settings = { ...DEFAULTS };
let tiled = false;
let toastTimer = null;

/* --- settings ------------------------------------------------------------ */

function load() {
  return new Promise((resolve) => {
    try {
      chrome.storage.local.get("omy", (got) => {
        if (!chrome.runtime.lastError && got && got.omy) {
          settings = { ...DEFAULTS, ...got.omy };
        }
        resolve();
      });
    } catch {
      resolve();
    }
  });
}

function save() {
  try {
    chrome.storage.local.set({ omy: settings });
  } catch {
    /* storage unavailable: settings stay per-window */
  }
}

function set(key, value) {
  settings[key] = value;
  save();
  applyClasses();
}

/* --- class plumbing ------------------------------------------------------ */

function applyClasses() {
  const html = document.documentElement;
  html.classList.toggle("omy-wide-grid", !!settings.wideGrid);
  html.classList.toggle("omy-tile", tiled);
  html.classList.toggle("omy-tile-fill", tiled && !!settings.fill);
}

/* --- tile mode ----------------------------------------------------------- */

function player() {
  return document.querySelector("#movie_player");
}

/* Hide everything outside the player's own subtree.
 *
 * Walking up from the player and hiding each ancestor's siblings covers every
 * overlay -- masthead, live chat, the theater-mode metadata row, engagement
 * panels -- without naming any of them, so it does not rot when YouTube
 * renames a container or introduces a new layout. Trying to enumerate them in
 * CSS meant a new bug for every page variant. */

const HIDDEN_CLASS = "omy-hidden";
const OWN_IDS = new Set(["omy-toast", "omy-settings-host"]);
const NEVER_HIDE = new Set(["STYLE", "SCRIPT", "LINK", "HEAD", "META", "TITLE"]);

let isolationObserver = null;
let isolationTimer = null;

function isolatePlayer() {
  const start = player();
  if (!start) return;
  clearIsolation();
  let node = start;
  while (node.parentElement) {
    for (const sibling of node.parentElement.children) {
      if (sibling === node) continue;
      if (OWN_IDS.has(sibling.id)) continue;
      if (NEVER_HIDE.has(sibling.tagName)) continue;
      sibling.classList.add(HIDDEN_CLASS);
    }
    node = node.parentElement;
  }
}

function clearIsolation() {
  // Snapshot first: getElementsByClassName is live, so removing the class
  // while iterating it skips every other element.
  for (const el of Array.from(document.getElementsByClassName(HIDDEN_CLASS))) {
    el.classList.remove(HIDDEN_CLASS);
  }
}

/* Live chat, engagement panels and endscreens are injected after the page
 * settles, so re-isolate as the DOM changes -- debounced, because YouTube
 * mutates constantly. */
function watchIsolation() {
  if (isolationObserver) return;
  isolationObserver = new MutationObserver(() => {
    clearTimeout(isolationTimer);
    isolationTimer = setTimeout(() => tiled && isolatePlayer(), 250);
  });
  isolationObserver.observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
}

function unwatchIsolation() {
  if (!isolationObserver) return;
  isolationObserver.disconnect();
  isolationObserver = null;
  clearTimeout(isolationTimer);
}

function isWatch() {
  return location.pathname === "/watch";
}

function enterTile() {
  if (tiled || !player()) return;
  // Real fullscreen and tile mode are mutually exclusive: one owns the
  // monitor, the other owns the tile.
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  tiled = true;
  applyClasses();
  isolatePlayer();
  watchIsolation();
  relayout();
  toast(settings.fill ? "Tile · fill" : "Tile");
}

function exitTile(quiet) {
  if (!tiled) return;
  tiled = false;
  unwatchIsolation();
  clearIsolation();
  applyClasses();
  relayout();
  if (!quiet) toast("Tile off");
}

function toggleTile() {
  tiled ? exitTile() : enterTile();
}

function toggleFill() {
  if (!tiled) return;
  set("fill", !settings.fill);
  relayout();
  toast(settings.fill ? "Tile · fill" : "Tile · fit");
}

/* The player computes scrubber and chrome geometry on resize. The window size
 * never changes when we toggle tile mode, so tell it to re-measure. */
function relayout() {
  const fire = () => window.dispatchEvent(new Event("resize"));
  fire();
  setTimeout(fire, 60);
  setTimeout(fire, 300);
}

/* --- toast --------------------------------------------------------------- */

function toast(text) {
  const host = document.body || document.documentElement;
  if (!host) return;
  let el = document.getElementById("omy-toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "omy-toast";
    host.appendChild(el);
  }
  el.textContent = text;
  el.dataset.show = "1";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    el.dataset.show = "0";
  }, 900);
}

/* --- keyboard ------------------------------------------------------------ */

function isTyping(target) {
  if (!target) return false;
  if (target.isContentEditable) return true;
  const tag = target.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
}

function onKeyDown(e) {
  if (e.ctrlKey || e.metaKey) return;
  if (isTyping(e.composedPath ? e.composedPath()[0] : e.target)) return;
  if (isTyping(e.target)) return;

  const key = e.key;

  // Alt+S: settings overlay (the only UI reachable in an --app window, which
  // has no toolbar and therefore no extension popup).
  if (e.altKey && (key === "s" || key === "S")) {
    e.preventDefault();
    e.stopImmediatePropagation();
    toggleSettings();
    return;
  }
  if (e.altKey) return;

  if ((key === "f" || key === "F") && settings.remapF) {
    // Shift+F is left alone so YouTube still gives you real monitor
    // fullscreen when you actually want it.
    if (e.shiftKey) return;
    if (!player()) return;
    e.preventDefault();
    e.stopImmediatePropagation();
    toggleTile();
    return;
  }

  if ((key === "z" || key === "Z") && !e.shiftKey && tiled) {
    e.preventDefault();
    e.stopImmediatePropagation();
    toggleFill();
    return;
  }

  if (key === "Escape") {
    if (settingsOpen()) {
      e.preventDefault();
      e.stopImmediatePropagation();
      closeSettings();
      return;
    }
    if (tiled) {
      e.preventDefault();
      e.stopImmediatePropagation();
      exitTile();
    }
  }
}

function onDblClick(e) {
  if (!settings.remapF) return;
  const path = e.composedPath ? e.composedPath() : [e.target];
  const onPlayer = path.some(
    (n) => n && n.id === "movie_player",
  );
  if (!onPlayer) return;
  // YouTube's double-click means real fullscreen; make it mean tile.
  e.preventDefault();
  e.stopImmediatePropagation();
  toggleTile();
}

/* --- navigation ---------------------------------------------------------- */

function waitForPlayer(timeout = 8000) {
  return new Promise((resolve) => {
    if (player()) return resolve(player());
    const started = performance.now();
    const obs = new MutationObserver(() => {
      const p = player();
      if (p) {
        obs.disconnect();
        resolve(p);
      } else if (performance.now() - started > timeout) {
        obs.disconnect();
        resolve(null);
      }
    });
    obs.observe(document.documentElement, { childList: true, subtree: true });
    setTimeout(() => {
      obs.disconnect();
      resolve(player());
    }, timeout);
  });
}

async function onNavigate() {
  if (!isWatch()) {
    exitTile(true);
    return;
  }
  if (!settings.autoTile || tiled) return;
  const p = await waitForPlayer();
  if (p && isWatch() && settings.autoTile) enterTile();
}

/* --- settings overlay ---------------------------------------------------- */

const ROWS = [
  ["autoTile", "Open videos in tile mode", "Fill the tile as soon as a video opens"],
  ["fill", "Zoom to fill", "Crop to the tile instead of letterboxing (z)"],
  ["remapF", "f = tile, Shift+F = fullscreen", "Keep f inside the tiling layout"],
  ["wideGrid", "Wide grid", "Use the tile's full width for the video grid"],
];

let panel = null;

function settingsOpen() {
  return !!panel;
}

function toggleSettings() {
  settingsOpen() ? closeSettings() : openSettings();
}

function closeSettings() {
  if (panel) panel.remove();
  panel = null;
}

function openSettings() {
  const host = document.createElement("div");
  host.id = "omy-settings-host";
  host.style.cssText =
    "position:fixed;inset:0;z-index:2147483647;display:flex;align-items:center;justify-content:center;";
  const root = host.attachShadow({ mode: "open" });

  const style = document.createElement("style");
  style.textContent = `
    :host { all: initial; }
    .backdrop { position:absolute; inset:0; background:rgba(0,0,0,.55); }
    .panel {
      position:relative; min-width:360px; max-width:88vw; padding:18px 20px;
      background: var(--bg, #16161e); color: var(--fg, #c0caf5);
      border:1px solid var(--accent, #7aa2f7); border-radius:8px;
      font:14px/1.45 "CaskaydiaMono Nerd Font", ui-monospace, monospace;
      box-shadow:0 10px 40px rgba(0,0,0,.6);
    }
    h1 { margin:0 0 14px; font-size:13px; letter-spacing:.12em;
         text-transform:uppercase; color: var(--accent, #7aa2f7); font-weight:600; }
    label { display:flex; gap:12px; align-items:flex-start; padding:7px 0; cursor:pointer; }
    input { margin:3px 0 0; accent-color: var(--accent, #7aa2f7); width:15px; height:15px; }
    .t { display:block; }
    .d { display:block; font-size:12px; opacity:.6; }
    footer { margin-top:14px; padding-top:12px; border-top:1px solid var(--muted, #414868);
             font-size:12px; opacity:.65; display:grid; grid-template-columns:auto 1fr; gap:2px 12px; }
    kbd { font-family:inherit; color: var(--accent, #7aa2f7); }
  `;

  const panelEl = document.createElement("div");
  panelEl.className = "panel";
  panelEl.innerHTML = "<h1>Omarchy Tile Mode</h1>";

  for (const [key, title, desc] of ROWS) {
    const label = document.createElement("label");
    const box = document.createElement("input");
    box.type = "checkbox";
    box.checked = !!settings[key];
    box.addEventListener("change", () => {
      set(key, box.checked);
      if (key === "fill") relayout();
    });
    const text = document.createElement("span");
    text.innerHTML = `<span class="t"></span><span class="d"></span>`;
    text.querySelector(".t").textContent = title;
    text.querySelector(".d").textContent = desc;
    label.append(box, text);
    panelEl.appendChild(label);
  }

  const footer = document.createElement("footer");
  for (const [k, v] of [
    ["f", "toggle tile mode"],
    ["Shift+F", "real fullscreen"],
    ["z", "zoom to fill"],
    ["Esc", "leave tile mode"],
    ["Alt+S", "these settings"],
  ]) {
    const kb = document.createElement("kbd");
    kb.textContent = k;
    const d = document.createElement("span");
    d.textContent = v;
    footer.append(kb, d);
  }
  panelEl.appendChild(footer);

  const backdrop = document.createElement("div");
  backdrop.className = "backdrop";
  backdrop.addEventListener("click", closeSettings);

  root.append(style, backdrop, panelEl);
  (document.body || document.documentElement).appendChild(host);
  panel = host;
}

/* --- boot ---------------------------------------------------------------- */

(async function init() {
  applyClasses(); // defaults first, so there is no unstyled flash
  await load();
  applyClasses();

  document.addEventListener("keydown", onKeyDown, true);
  document.addEventListener("dblclick", onDblClick, true);

  // Real fullscreen wins if the user explicitly asks for it.
  document.addEventListener("fullscreenchange", () => {
    if (document.fullscreenElement && tiled) exitTile(true);
    else relayout();
  });

  window.addEventListener("yt-navigate-finish", onNavigate);
  window.addEventListener("popstate", onNavigate);

  // Fallback for SPA transitions that do not emit yt-navigate-finish.
  let lastHref = location.href;
  setInterval(() => {
    if (location.href !== lastHref) {
      lastHref = location.href;
      onNavigate();
    }
  }, 500);

  try {
    chrome.storage.onChanged.addListener((changes, area) => {
      if (area !== "local" || !changes.omy) return;
      settings = { ...DEFAULTS, ...changes.omy.newValue };
      applyClasses();
    });
  } catch {
    /* ignore */
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", onNavigate, { once: true });
  } else {
    onNavigate();
  }
})();
