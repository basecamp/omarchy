// Follows the active Omarchy theme's light/dark for WhatsApp Web.
//
// The shared theme bridge (com.omarchy.theme) pushes the current theme to the
// service worker, which broadcasts it here. We decide dark vs. light from the
// WCAG relative luminance of the terminal background — not the theme's day/night
// name — then hand that to the MAIN-world prefers-color-scheme shim
// (omarchy-prefers-color-scheme.js). The shim flips window.matchMedia, so
// WhatsApp Web's "System default" theme repaints live with no reload.
//
// That's the whole extension: WhatsApp themes itself, so there's no CSS to
// inject. Matching WhatsApp's surfaces to the exact omarchy palette would be a
// separate, heavier layer and is intentionally left out of this version.

// sRGB is gamma-encoded, so the WCAG weights only mean anything once each
// channel is linearized — the same two steps the shell uses in
// Panel.qml's colorChannelLuminance. Weighting the raw bytes instead lands
// mid-tone backgrounds on the wrong side: #808080 reads 0.502 that way and
// 0.216 once linearized. Every shipped theme is far enough from the middle to
// classify the same either way; a custom one need not be.
function channelLuminance(byte) {
  const channel = byte / 255;
  return channel <= 0.03928
    ? channel / 12.92
    : Math.pow((channel + 0.055) / 1.055, 2.4);
}

function isDarkTheme(theme) {
  const hex = ((theme && theme.bg) || "").replace(/^#/, "");
  if (hex.length < 6) return null;
  const r = parseInt(hex.slice(0, 2), 16);
  const g = parseInt(hex.slice(2, 4), 16);
  const b = parseInt(hex.slice(4, 6), 16);
  if ([r, g, b].some(Number.isNaN)) return null;
  const luminance =
    0.2126 * channelLuminance(r) +
    0.7152 * channelLuminance(g) +
    0.0722 * channelLuminance(b);
  return luminance < 0.5;
}

let lastDark = null;

function applyTheme(theme) {
  const dark = isDarkTheme(theme);
  if (dark === null || dark === lastDark) return;
  lastDark = dark;
  document.documentElement.style.colorScheme = dark ? "dark" : "light";
  document.dispatchEvent(
    new CustomEvent("omarchy:set-color-scheme", { detail: { dark } })
  );
}

// Themes arrive two ways: pushed live by the service worker on an omarchy
// theme-set, and fetched once on load.
chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === "omarchy-theme") applyTheme(msg.theme);
});
chrome.runtime.sendMessage({ type: "request-theme" }, (theme) => {
  if (theme) applyTheme(theme);
});
