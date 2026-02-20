const copyActiveTabUrl = () => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const currentTab = tabs[0];
    if (!currentTab || !currentTab.id || !currentTab.url) {
      return;
    }

    const restrictedSchemes = ['chrome://', 'chrome-extension://', 'chrome-devtools://'];
    if (restrictedSchemes.some((scheme) => currentTab.url.startsWith(scheme))) {
      return;
    }

    chrome.scripting.executeScript({
      target: { tabId: currentTab.id },
      func: () => {
        navigator.clipboard.writeText(window.location.href);
      }
    }).then(() => {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
        title: '   URL copied to clipboard',
        message: '',
      }).then((notificationId) => {
        // Auto-close the notification so it doesn't linger indefinitely.
        setTimeout(() => {
          chrome.notifications.clear(notificationId);
        }, 4000);
      });
    });
  });
};

chrome.commands.onCommand.addListener((command) => {
  if (command === 'copy-url') {
    copyActiveTabUrl();
  }
});

chrome.action.onClicked.addListener(() => {
  copyActiveTabUrl();
});
