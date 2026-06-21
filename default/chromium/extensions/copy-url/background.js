chrome.commands.onCommand.addListener((command) => {
  if (command === 'copy-url') {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const currentTab = tabs[0];

      chrome.scripting.executeScript({
        target: { tabId: currentTab.id },
        func: () => {
          const url = new URL(window.location.href);
          const outlookMailMatch = url.pathname.match(/^\/mail\/inbox\/id\/(.+)$/);

          if (url.origin === 'https://outlook.office.com' && outlookMailMatch) {
            navigator.clipboard.writeText(`https://outlook.office365.com/owa/?exvsurl=1&viewmodel=ReadMessageItem&ItemID=${outlookMailMatch[1]}`);
          } else {
            navigator.clipboard.writeText(window.location.href);
          }
        }
      }).then(() => {
        chrome.notifications.create({
          type: 'basic',
          iconUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
          title: '   URL copied to clipboard',
          message: ''
        });
      });
    });
  }
});
