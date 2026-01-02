async function copyToClipboard(text) {
  await chrome.offscreen.createDocument({
    url: 'offscreen.html',
    reasons: ['CLIPBOARD'],
    justification: 'Copy URL to clipboard'
  }).catch(() => {});

  await chrome.runtime.sendMessage({ type: 'copy', text });

  await chrome.offscreen.closeDocument().catch(() => {});
}

chrome.commands.onCommand.addListener(async (command) => {
  if (command === 'copy-url') {
    const [currentTab] = await chrome.tabs.query({ active: true, currentWindow: true });

    await copyToClipboard(currentTab.url);

    chrome.notifications.create({
      type: 'basic',
      iconUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
      title: '   URL copied to clipboard',
      message: ''
    });
  }
});
