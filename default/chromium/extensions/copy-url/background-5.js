// Keep this filename versioned. Chromium caches service workers for extensions
// loaded via --load-extension, so a new URL forces registration of new code.

function copyUrl(url) {
  if (!url) return;

  // The native host owns both the Wayland clipboard and confirmation toast.
  chrome.runtime.sendNativeMessage('com.omarchy.copy_url', { url }, () => {
    void chrome.runtime.lastError;
  });
}

chrome.commands.onCommand.addListener((command) => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const [tab] = tabs;
    const url = tab?.url;
    if (!url) return;
    if (command === 'copy-url') {
      copyUrl(url);
    } else if (command === 'copy-markdown-link') {
      const title = tab.title || url;
      // The title might contain brackets, which must be escaped inside the Markdown link.
      const escaped = title.replace(/([\\[\]])/g, '\\$1');
      copyUrl(`[${escaped}](<${url}>)`);
    }
  });
});

chrome.action.onClicked.addListener((tab) => {
  copyUrl(tab && tab.url);
});
