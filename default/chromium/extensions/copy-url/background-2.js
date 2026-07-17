// NOTE: this file is intentionally version-numbered (background-2.js). Chromium
// caches the service worker for a command-line --load-extension and does NOT
// re-register it when the script changes in place, so an updated worker never
// takes effect on existing installs. Changing the filename is a new script URL,
// which forces a fresh registration. If you change this worker's code, rename it
// (background-3.js, ...) and update manifest.json's background.service_worker.

let creatingOffscreenDocument;

async function ensureOffscreenDocument() {
  if (await chrome.offscreen.hasDocument()) return;

  if (!creatingOffscreenDocument) {
    creatingOffscreenDocument = chrome.offscreen.createDocument({
      url: 'offscreen.html',
      reasons: ['CLIPBOARD'],
      justification: 'Copy the active tab URL to the clipboard'
    }).finally(() => {
      creatingOffscreenDocument = undefined;
    });
  }

  await creatingOffscreenDocument;
}

async function copyUrl(url) {
  if (!url) return;

  try {
    await ensureOffscreenDocument();
    const copied = await chrome.runtime.sendMessage({
      target: 'offscreen',
      type: 'copy-url',
      url
    });

    if (!copied) return;

    // The omarchy notification shell renders a chromium toast slim (no icon
    // slot) when the summary begins with a glyph followed by 2+ spaces and the
    // body is empty. iconUrl is a required field, so keep a 1x1 transparent png.
    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
      title: '󰅍   URL copied to clipboard',
      message: ''
    });
  } catch (error) {
    console.error('[copy-url] failed:', error);
  }
}

// Keyboard shortcut (Alt+Shift+L).
chrome.commands.onCommand.addListener((command) => {
  if (command !== 'copy-url') return;

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    copyUrl(tabs[0] && tabs[0].url);
  });
});

// Clicking the extension's toolbar icon.
chrome.action.onClicked.addListener((tab) => {
  copyUrl(tab && tab.url);
});
