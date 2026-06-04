function sendUrl(url) {
  if (!url || !/^https?:/i.test(url)) return;

  // The native messaging host runs yt-dlp and owns all the desktop
  // notifications, so we just hand off the URL and ignore the reply.
  chrome.runtime.sendNativeMessage('com.omarchy.ytdlp', { url }, () => {
    void chrome.runtime.lastError;
  });
}

function triggerDownload(tab) {
  if (!tab) return;

  // The activeTab permission exposes tab.url whenever the user invokes the
  // extension — both via the toolbar click and the keyboard shortcut.
  if (tab.url) {
    sendUrl(tab.url);
    return;
  }

  // Fallback: read the URL straight from the page.
  if (tab.id === undefined) return;
  chrome.scripting
    .executeScript({ target: { tabId: tab.id }, func: () => location.href })
    .then((results) => sendUrl(results && results[0] && results[0].result))
    .catch(() => {});
}

// Keyboard shortcut (Alt+Shift+D).
chrome.commands.onCommand.addListener((command) => {
  if (command === 'download-video') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      triggerDownload(tabs[0]);
    });
  }
});

// Clicking the extension's toolbar icon.
chrome.action.onClicked.addListener((tab) => {
  triggerDownload(tab);
});
