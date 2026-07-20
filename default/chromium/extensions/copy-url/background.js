chrome.commands.onCommand.addListener(async (command) => {
  if (command !== 'copy-url') return;

  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) return;

    // Copy via offscreen document — works on all pages including
    // restricted ones (chrome://, brave://) and doesn't require
    // user activation in the page context.
    const contexts = await chrome.runtime.getContexts({
      contextTypes: ['OFFSCREEN_DOCUMENT']
    });
    if (!contexts.length) {
      await chrome.offscreen.createDocument({
        url: 'offscreen.html',
        reasons: ['CLIPBOARD'],
        justification: 'Copy URL to clipboard'
      });
    }

    const result = await chrome.runtime.sendMessage({ target: 'offscreen', text: tab.url });

    if (result?.success) {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'icon.png',
        title: 'URL copied to clipboard',
        message: tab.url
      });
    } else {
      chrome.notifications.create({
        type: 'basic',
        iconUrl: 'icon.png',
        title: 'Failed to copy URL',
        message: 'Clipboard write failed'
      });
    }

    // Close the offscreen document — no need to keep it alive
    chrome.offscreen.closeDocument().catch(() => {});
  } catch (e) {
    console.error('copy-url:', e);
  }
});
