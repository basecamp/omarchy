// Keep this filename versioned. Chromium caches service workers for extensions
// loaded via --load-extension, so a new URL forces registration of new code.

function sendPageAction(action, url) {
  if (!url) return;

  chrome.runtime.sendNativeMessage('com.omarchy.copy_url', { action, url }, () => {
    void chrome.runtime.lastError;
  });
}

chrome.commands.onCommand.addListener((command) => {
  if (command !== 'copy-url' && command !== 'subscribe-feed') return;

  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    sendPageAction(command, tabs[0] && tabs[0].url);
  });
});

chrome.action.onClicked.addListener((tab) => {
  sendPageAction('copy-url', tab && tab.url);
});
