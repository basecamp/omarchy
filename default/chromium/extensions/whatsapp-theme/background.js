// MV3 service worker for the Omarchy WhatsApp theme extension.
//
// Holds the long-lived native-messaging port to the shared Omarchy theme bridge
// (com.omarchy.theme / omarchy-chromium-theme-host), which pushes the active
// theme on connect and on every omarchy theme-set. We rebroadcast pushes to
// WhatsApp tabs and answer the content script's theme requests. We never write
// to the port — the host is push-only.

const HOST = "com.omarchy.theme";
const WHATSAPP_URL_PATTERNS = ["*://web.whatsapp.com/*"];

let port = null;
let reconnectTimer = null;

function connect() {
  // The service worker can reach this from three directions at once: the
  // module-level call below, onInstalled, and onStartup. Without this guard each
  // one opens its own port, and every port spawns a separate long-lived native
  // host — so the theme-set refresh then signals N hosts and every theme change
  // gets broadcast to the same tabs N times.
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
    console.log("[omarchy] native port connected");
  } catch (e) {
    console.warn("[omarchy] connectNative threw:", e);
    scheduleReconnect();
    return;
  }

  port.onMessage.addListener((theme) => {
    if (!theme || theme.error) {
      console.warn("[omarchy] native host error:", theme && theme.error);
      return;
    }
    console.log("[omarchy] theme pushed by native host:", theme.theme_name, theme.bg);
    chrome.storage.local.set({ theme });
    broadcast(theme);
  });

  port.onDisconnect.addListener(() => {
    const err = chrome.runtime.lastError;
    console.warn("[omarchy] native host disconnected:", err && err.message);
    port = null;
    scheduleReconnect();
  });

  // No request needed: the host is push-only. It emits the current theme as soon
  // as it starts, then again on every theme change (driven by omarchy's
  // theme-set refresh). We never write to the port.
}

function scheduleReconnect() {
  if (reconnectTimer) return;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, 3000);
}

function broadcast(theme) {
  chrome.tabs.query({ url: WHATSAPP_URL_PATTERNS }, (tabs) => {
    console.log("[omarchy] broadcasting theme to", tabs.length, "whatsapp tab(s)");
    for (const t of tabs) {
      chrome.tabs.sendMessage(t.id, { type: "omarchy-theme", theme }).catch(() => {});
    }
  });
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg && msg.type === "request-theme") {
    chrome.storage.local.get("theme").then(({ theme }) => sendResponse(theme || null));
    return true;
  }
  // Kept for parity with the shared engine, which asks for a guaranteed-current
  // theme right before it would drive an app's own color mode. Storage is
  // already current: omarchy fires its theme-set refresh after the new theme's
  // files are final, the host pushes immediately, and we write storage on that
  // push — all before the content script gets the broadcast that makes it ask.
  if (msg && msg.type === "request-fresh-theme") {
    chrome.storage.local.get("theme").then(({ theme }) => sendResponse(theme || null));
    return true;
  }
});

// The WhatsApp host permission is what grants tab urls here and lets the query
// above filter by url, so the `tabs` permission — which would hand over every
// tab's url and title — is not needed. Tabs we have no permission for arrive
// with url unset and fall out on the guard below. If a url ever went missing on
// a tab we do own, content.js still asks for the theme itself at document_start,
// so this listener is the redundant path rather than the only one.
chrome.tabs.onUpdated.addListener((tabId, info, tab) => {
  if (info.status !== "complete") return;
  if (!tab.url || !tab.url.includes("web.whatsapp.com")) return;
  chrome.storage.local.get("theme").then(({ theme }) => {
    if (theme) chrome.tabs.sendMessage(tabId, { type: "omarchy-theme", theme }).catch(() => {});
  });
});

chrome.runtime.onInstalled.addListener(connect);
chrome.runtime.onStartup.addListener(connect);

connect();
