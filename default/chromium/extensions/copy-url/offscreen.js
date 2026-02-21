chrome.runtime.onMessage.addListener((message) => {
  if (message.type === 'copy') {
    const textArea = document.getElementById('text');
    textArea.value = message.text;
    textArea.select();
    document.execCommand('copy');
  }
});
