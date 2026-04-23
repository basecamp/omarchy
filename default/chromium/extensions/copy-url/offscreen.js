chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.target !== 'offscreen' || !msg.text) return;
  const ta = document.createElement('textarea');
  ta.value = msg.text;
  document.body.appendChild(ta);
  ta.select();
  let success = false;
  try {
    success = document.execCommand('copy');
  } catch (e) {
    success = false;
  }
  ta.remove();
  sendResponse({ success });
  return true;
});
