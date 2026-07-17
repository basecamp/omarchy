chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.target !== 'offscreen' || message.type !== 'copy-url') return;

  // Offscreen documents are never focused, so navigator.clipboard.writeText
  // rejects with "Document is not focused". execCommand('copy') has no focus
  // requirement and is authorized by the clipboardWrite permission.
  try {
    const target = document.getElementById('target');
    target.value = message.url;
    target.focus();
    target.select();
    sendResponse(document.execCommand('copy'));
  } catch (error) {
    console.error('[copy-url offscreen] error:', error);
    sendResponse(false);
  }
});
