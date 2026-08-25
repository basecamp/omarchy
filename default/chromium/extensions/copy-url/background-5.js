// Keep this filename versioned. Chromium caches service workers for extensions
// loaded via --load-extension, so a new URL forces registration of new code.

function copyUrl(url) {
  if (!url) return;

  // The native host owns both the Wayland clipboard and confirmation toast.
  chrome.runtime.sendNativeMessage('com.omarchy.copy_url', { url }, () => {
    void chrome.runtime.lastError;
  });
}

function copyMarkdownLink(tab) {
  if (!tab || !tab.url) return;

  copyUrl(`[${tab.title || tab.url}](<${tab.url}>)`);
}

chrome.commands.onCommand.addListener((command) => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    if (command === 'copy-url') {
      copyUrl(tabs[0] && tabs[0].url);
    } else if (command === 'copy-markdown-link') {
      copyMarkdownLink(tabs[0]);
    }
  });
});

chrome.action.onClicked.addListener((tab) => {
  copyUrl(tab && tab.url);
});
